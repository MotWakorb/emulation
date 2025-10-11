<# 
.SYNOPSIS
  Convert ROM archives & images to CHD on Windows (PowerShell).

.DESCRIPTION
  - Extracts .7z/.zip archives (requires 7-Zip CLI: 7zz.exe or 7z.exe)
  - Converts .iso/.gcm (DVD) and .cue/.gdi/.toc (CD) to .chd via chdman.exe (from MAME)
  - Parallel processing via PS7 ForEach-Object -Parallel or Start-Job
  - Per-title logs; colored console output (TTY-aware)
  - Optional OUT_DIR (mirrors source tree), DRYRUN mode, dependency preflight
  - Optional AUTO_INSTALL using winget or choco (if available)

.PARAMETER RomDir
  Root folder containing ROMs. Default: $env:ROM_DIR or 'C:\path\to\roms'

.PARAMETER Recursive
  Recurse into subfolders. Default: $env:RECURSIVE or $false

.PARAMETER Jobs
  Max parallel workers. Default: min(logical cores, 6). Can be overridden or via $env:JOBS

.PARAMETER OutDir
  Write CHDs under this root, mirroring the source tree. Default: $env:OUT_DIR (unset = alongside sources)

.PARAMETER LogDir
  Folder for per-title logs. Default: $env:LOG_DIR or '<RomDir>\.chd_logs'

.PARAMETER DryRun
  Print planned actions only; make no changes. Default: $env:DRYRUN or $false

.PARAMETER CheckOnly
  Check dependencies and exit. Default: $env:CHECK_ONLY or $false

.PARAMETER AutoInstall
  Attempt to auto-install deps using winget or choco. Default: $env:AUTO_INSTALL or $false

.PARAMETER Help
  Show usage and exit.
#>

param(
  [string]$RomDir = $(if ($env:ROM_DIR) { $env:ROM_DIR } else { 'C:\path\to\roms' }),
  [switch]$Recursive = $(if ($env:RECURSIVE) { [bool]::Parse(($env:RECURSIVE -as [string]).Replace('1','True').Replace('0','False')) } else { $false }),
  [int]$Jobs = $(
    if ($env:JOBS) { [int]$env:JOBS } 
    else { 
      try { 
        $n = [Environment]::ProcessorCount
        if ($n -gt 6) { 6 } else { $n }
      } catch { 4 }
    }
  ),
  [string]$OutDir = $(if ($env:OUT_DIR) { $env:OUT_DIR } else { '' }),
  [string]$LogDir = $(if ($env:LOG_DIR) { $env:LOG_DIR } else { '' }),
  [switch]$DryRun = $(if ($env:DRYRUN) { [bool]::Parse(($env:DRYRUN -as [string]).Replace('1','True').Replace('0','False')) } else { $false }),
  [switch]$CheckOnly = $(if ($env:CHECK_ONLY) { [bool]::Parse(($env:CHECK_ONLY -as [string]).Replace('1','True').Replace('0','False')) } else { $false }),
  [switch]$AutoInstall = $(if ($env:AUTO_INSTALL) { [bool]::Parse(($env:AUTO_INSTALL -as [string]).Replace('1','True').Replace('0','False')) } else { $false }),
  [switch]$Help
)

#region Colors & logging
$IsVT = $Host.UI.SupportsVirtualTerminal -or $env:WT_SESSION -or $env:ConEmuANSI -or $env:ANSICON
$NO_COLOR = [bool]($env:NO_COLOR)

function Color([string]$s, [string]$ansi) {
  if ($NO_COLOR -or -not $IsVT) { return $s }
  return "$ansi$s`e[0m"
}
$C_INFO = "`e[1;36m"
$C_WARN = "`e[1;33m"
$C_ERR  = "`e[1;31m"
$C_OK   = "`e[1;32m"
$C_DIM  = "`e[2m"
$C_BOLD = "`e[1m"

function Now { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
function Log([string]$msg) { Write-Host ("[{0}] {1}" -f (Now), (Color $msg $C_INFO)) }
function Warn([string]$msg){ Write-Host ("[{0}] {1}" -f (Now), (Color $msg $C_WARN)) }
function Ok([string]$msg)  { Write-Host ("[{0}] {1}" -f (Now), (Color $msg $C_OK)) }
function Err([string]$msg) { Write-Host ("[{0}] {1}" -f (Now), (Color $msg $C_ERR)) }

function Usage {
@"
$(Color (Split-Path -Leaf $PSCommandPath) $C_BOLD) — Convert ROM archives & images to CHD on Windows (PowerShell).

USAGE
  $(Split-Path -Leaf $PSCommandPath) [-RomDir <path>] [-Recursive] [-Jobs <N>] [-OutDir <path>] [-LogDir <path>] [-DryRun] [-CheckOnly] [-AutoInstall]
  Environment variable overrides are supported (ROM_DIR, RECURSIVE, JOBS, OUT_DIR, LOG_DIR, DRYRUN, CHECK_ONLY, AUTO_INSTALL).

EXAMPLES
  .\roms_to_chd.ps1 -CheckOnly
  .\roms_to_chd.ps1 -RomDir 'D:\Roms\ps2' -Recursive -Jobs 6
  .\roms_to_chd.ps1 -RomDir 'D:\Roms' -OutDir 'E:\CHD' -Recursive
  .\roms_to_chd.ps1 -DryRun -RomDir 'D:\Roms' -Recursive -LogDir 'D:\logs\chd'

DEPENDENCIES
  - 7-Zip CLI: 7zz.exe (preferred) or 7z.exe
  - chdman.exe (from MAME)
  Optional installers: winget or choco (used when -AutoInstall is set)

SUPPORTED INPUTS
  Archives: .7z, .zip
  CD images: .cue, .gdi, .toc
  DVD images: .iso, .gcm
  Unsupported directly: .wbfs, .cso, .nkit  (convert back to .iso first)
"@ | Write-Host
}
if ($Help) { Usage; exit 0 }
#endregion

#region Preflight (Windows)
function Which([string]$name) {
  $exts = ($env:PATHEXT -split ';')
  foreach ($dir in ($env:PATH -split ';')) {
    foreach ($e in @('') + $exts) {
      $p = Join-Path $dir ($name + $e)
      if (Test-Path $p) { return $p }
    }
  }
  return $null
}

$SevenZip = $null
$ChdMan   = $null

function Detect-Tools {
  Set-Variable -Scope Script -Name SevenZip -Value (Which '7zz') -ErrorAction SilentlyContinue
  if (-not $Script:SevenZip) {
    Set-Variable -Scope Script -Name SevenZip -Value (Which '7z') -ErrorAction SilentlyContinue
  }
  Set-Variable -Scope Script -Name ChdMan -Value (Which 'chdman') -ErrorAction SilentlyContinue
}

function Have-Cmd([string]$cmd) { return [bool](Which $cmd) }

function Try-AutoInstall {
  param([string[]]$Packages7zip, [string[]]$PackagesMame)
  if (-not $AutoInstall) { return }
  $hasWinget = Have-Cmd 'winget'
  $hasChoco  = Have-Cmd 'choco'
  if (-not $hasWinget -and -not $hasChoco) {
    Warn "AUTO_INSTALL requested but neither winget nor choco was found."
    return
  }
  if (-not $Script:SevenZip) {
    if ($hasWinget) { foreach ($p in $Packages7zip) { Log "winget install $p"; winget install --silent --accept-source-agreements --accept-package-agreements $p 2>$null | Out-Null; if (Have-Cmd '7zz' -or Have-Cmd '7z') { break } } }
    if (-not $Script:SevenZip -and $hasChoco) { foreach ($p in @('7zip')) { Log "choco install $p"; choco install -y $p 2>$null | Out-Null; if (Have-Cmd '7zz' -or Have-Cmd '7z') { break } } }
  }
  if (-not $Script:ChdMan) {
    if ($hasWinget) { foreach ($p in $PackagesMame) { Log "winget install $p"; winget install --silent --accept-source-agreements --accept-package-agreements $p 2>$null | Out-Null; if (Have-Cmd 'chdman') { break } } }
    if (-not $Script:ChdMan -and $hasChoco) { foreach ($p in @('mame')) { Log "choco install $p"; choco install -y $p 2>$null | Out-Null; if (Have-Cmd 'chdman') { break } } }
  }
  Detect-Tools
}

function Preflight {
  Detect-Tools

  if (-not (Test-Path $RomDir)) {
    Err "RomDir does not exist: $RomDir"
    exit 1
  }

  $need7z  = -not $Script:SevenZip
  $needChd = -not $Script:ChdMan

  if ($need7z -or $needChd) {
    Write-Host ""
    if ($need7z)  { Write-Host "Missing requirement: 7-Zip CLI (7zz.exe or 7z.exe)." }
    if ($needChd) { Write-Host "Missing requirement: chdman.exe (from MAME)." }
    Write-Host "You can install with:"
    Write-Host "  winget install 7zip.7zip         # 7-Zip"
    Write-Host "  winget install MAMEDev.MAME      # MAME (contains chdman.exe)"
    Write-Host "  -- OR --"
    Write-Host "  choco install 7zip"
    Write-Host "  choco install mame"

    if ($AutoInstall) {
      Try-AutoInstall -Packages7zip @('7zip.7zip','7zip.7zip-alpha','7zip.7zip-Beta') -PackagesMame @('MAMEDev.MAME')
    }
  }

  if (-not $Script:SevenZip -or -not $Script:ChdMan) {
    Err "Dependencies missing; aborting."
    exit 2
  }

  Ok "Preflight OK: using $([IO.Path]::GetFileName($Script:SevenZip)) and $([IO.Path]::GetFileName($Script:ChdMan))."
  if ($CheckOnly) {
    Warn "CheckOnly set; exiting after preflight."
    exit 0
  }
}
#endregion

#region Helpers
$DVD_EXTS = @('iso','gcm')
$CD_EXTS  = @('cue','gdi','toc')

function Get-Ext([string]$Path) { return ([IO.Path]::GetExtension($Path)).TrimStart('.').ToLowerInvariant() }
function Is-Dvd([string]$Path) { $e = Get-Ext $Path; return $DVD_EXTS -contains $e }
function Is-Cd ([string]$Path) { $e = Get-Ext $Path; return $CD_EXTS  -contains $e }

function DestDir-For([string]$SrcDir) {
  if ([string]::IsNullOrWhiteSpace($OutDir)) { return $SrcDir }
  $rom = (Resolve-Path -LiteralPath $RomDir).Path
  $src = (Resolve-Path -LiteralPath $SrcDir).Path
  $rel = if ($src.StartsWith($rom, [StringComparison]::OrdinalIgnoreCase)) { $src.Substring($rom.Length).TrimStart('\') } else { '' }
  if ($rel) { return (Join-Path $OutDir $rel) } else { return $OutDir }
}

function Ensure-Dir([string]$Dir) {
  if ($DryRun) { Log "DRYRUN: would mkdir '$Dir'"; return }
  if (-not (Test-Path -LiteralPath $Dir)) { New-Item -ItemType Directory -Path $Dir | Out-Null }
}

function CHD-PathFor([string]$SrcFile) {
  $srcDir = Split-Path -LiteralPath $SrcFile -Parent
  $base   = [IO.Path]::GetFileNameWithoutExtension($SrcFile)
  $outdir = DestDir-For $srcDir
  return (Join-Path $outdir ($base + '.chd'))
}

function Sanitize-Title([string]$Title) {
  $t = $Title -replace '\s','_'
  $t = ($t -replace '[^A-Za-z0-9_\.\-]','')
  return $t
}

function Log-PathFor([string]$Title) {
  $base = Sanitize-Title $Title
  return (Join-Path $LogDir ($base + '.log'))
}

function Cue-ListSources([string]$CuePath) {
  $dir = Split-Path -LiteralPath $CuePath -Parent
  $files = @()
  Get-Content -LiteralPath $CuePath | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^\s*FILE\s+"?(.+?)"?\s+\w+\s*$') {
      $ref = $matches[1]
      $full = Join-Path $dir $ref
      if (Test-Path -LiteralPath $full) { $files += $full }
    }
  }
  return $files
}

function Run-Logged([string]$LogFile, [string[]]$Cmd, [switch]$Quiet=$false) {
  $line = "[{0}] RUN: {1}" -f (Now), ($Cmd -join ' ')
  Add-Content -LiteralPath $LogFile -Value $line
  if ($DryRun) { Log ("DRYRUN: " + ($Cmd -join ' ')); return @{ ExitCode = 0 } }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName  = $Cmd[0]
  $psi.Arguments = ($Cmd[1..($Cmd.Length-1)] -join ' ')
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true
  $psi.UseShellExecute = $false
  $p = New-Object System.Diagnostics.Process
  $p.StartInfo = $psi
  [void]$p.Start()
  $stdout = $p.StandardOutput.ReadToEnd()
  $stderr = $p.StandardError.ReadToEnd()
  $p.WaitForExit()
  if (-not $Quiet) {
    if ($stdout) { Add-Content -LiteralPath $LogFile -Value $stdout }
    if ($stderr) { Add-Content -LiteralPath $LogFile -Value $stderr }
  }
  return @{ ExitCode = $p.ExitCode; StdOut = $stdout; StdErr = $stderr }
}

function Safe-Cleanup([string]$ChdPath, [string]$LogFile, [string[]]$Sources) {
  if ($DryRun) { 
    Add-Content -LiteralPath $LogFile -Value ("[{0}] DRYRUN: would delete: {1}" -f (Now), ($Sources -join ', '))
    return 
  }
  if ((Test-Path -LiteralPath $ChdPath) -and ((Get-Item -LiteralPath $ChdPath).Length -gt 0)) {
    foreach ($s in $Sources) {
      if (Test-Path -LiteralPath $s) {
        Add-Content -LiteralPath $LogFile -Value ("[{0}] DELETE: {1}" -f (Now), $s)
        Remove-Item -LiteralPath $s -Force
      }
    }
  }
}
#endregion

#region Core steps
function Process-Extracted([string]$WorkDir, [string]$BaseNoExt, [string]$SrcDir, [string]$LogFile) {
  $destDir = DestDir-For $SrcDir
  Ensure-Dir $destDir
  $chd = Join-Path $destDir ($BaseNoExt + '.chd')

  $desc = Get-ChildItem -LiteralPath $WorkDir -Filter *.cue -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $desc) { $desc = Get-ChildItem -LiteralPath $WorkDir -Filter *.gdi -File -ErrorAction SilentlyContinue | Select-Object -First 1 }
  if (-not $desc) { $desc = Get-ChildItem -LiteralPath $WorkDir -Filter *.toc -File -ErrorAction SilentlyContinue | Select-Object -First 1 }

  if ($desc) {
    Log "Converting (CD) $BaseNoExt -> $(Split-Path -Leaf $chd)"
    $res = Run-Logged $LogFile @($Script:ChdMan, 'createcd', '-i', $desc.FullName, '-o', $chd)
    $tracks = Cue-ListSources $desc.FullName
    Safe-Cleanup $chd $LogFile (@($desc.FullName) + $tracks)
    return $true
  }

  $dvd = Get-ChildItem -LiteralPath $WorkDir -Include *.iso,*.gcm -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($dvd) {
    Log "Converting (DVD) $BaseNoExt -> $(Split-Path -Leaf $chd)"
    $res = Run-Logged $LogFile @($Script:ChdMan, 'createdvd', '-i', $dvd.FullName, '-o', $chd)
    Safe-Cleanup $chd $LogFile @($dvd.FullName)
    return $true
  }

  Warn "No convertible image found for $BaseNoExt — skipping."
  return $false
}

function Process-Archive([string]$ArchivePath) {
  $srcDir = Split-Path -LiteralPath $ArchivePath -Parent
  $file   = Split-Path -Leaf $ArchivePath
  $baseNo = [IO.Path]::GetFileNameWithoutExtension($file)
  $logFile = Log-PathFor $baseNo
  "Title: $baseNo`nSource: $ArchivePath`n" | Set-Content -LiteralPath $logFile

  Log "Extracting: $file"
  if ($DryRun) { Add-Content -LiteralPath $logFile -Value ("[{0}] DRYRUN: would extract `"{1}`"" -f (Now), $ArchivePath); return }

  $tmpBase = [IO.Path]::Combine([IO.Path]::GetTempPath(), (".extract_{0}_{1}" -f $baseNo, ([System.Guid]::NewGuid().ToString('N').Substring(0,8))))
  New-Item -ItemType Directory -Path $tmpBase | Out-Null

  $res = Run-Logged $logFile @($Script:SevenZip, 'x', '-y', "-o$tmpBase", '--', $ArchivePath)
  if ($res.ExitCode -ne 0) {
    Err "Extraction failed: $file"
    Add-Content -LiteralPath $logFile -Value ("[{0}] ERROR: extraction failed for {1}" -f (Now), $file)
    Remove-Item -LiteralPath $tmpBase -Force -Recurse
    return
  }

  if (Process-Extracted -WorkDir $tmpBase -BaseNoExt $baseNo -SrcDir $srcDir -LogFile $logFile) {
    $dst = Join-Path (DestDir-For $srcDir) ($baseNo + '.chd')
    if ((Test-Path $dst) -and ((Get-Item $dst).Length -gt 0)) {
      Ok "Success: $($baseNo).chd created. Cleaning archive."
      Add-Content -LiteralPath $logFile -Value ("[{0}] SUCCESS: created CHD" -f (Now))
      Safe-Cleanup $dst $logFile @($ArchivePath)
    } else {
      Warn "CHD not created for $file; leaving archive."
      Add-Content -LiteralPath $logFile -Value ("[{0}] WARN: CHD not created; archive kept" -f (Now))
    }
  }
  Remove-Item -LiteralPath $tmpBase -Force -Recurse
}

function Process-Loose([string]$Path) {
  $stem  = [IO.Path]::Combine((Split-Path -Parent $Path), ([IO.Path]::GetFileNameWithoutExtension($Path)))
  $title = [IO.Path]::GetFileName($stem)
  $logFile = Log-PathFor $title
  "Title: $title`nSource: $Path`n" | Set-Content -LiteralPath $logFile

  $chd = CHD-PathFor $Path
  if ((Test-Path $chd) -and ((Get-Item $chd).Length -gt 0)) {
    Warn "CHD already exists for $(Split-Path -Leaf $Path); skipping."
    Add-Content -LiteralPath $logFile -Value ("[{0}] SKIP: CHD already exists: {1}" -f (Now), $chd)
    return
  }

  if (Is-Cd $Path) {
    Log "Converting (CD) $title -> $(Split-Path -Leaf $chd)"
    $res = Run-Logged $logFile @($Script:ChdMan, 'createcd', '-i', $Path, '-o', $chd)
    $refs = Cue-ListSources $Path
    Safe-Cleanup $chd $logFile (@($Path) + $refs)
  } elseif (Is-Dvd $Path) {
    Log "Converting (DVD) $title -> $(Split-Path -Leaf $chd)"
    $res = Run-Logged $logFile @($Script:ChdMan, 'createdvd', '-i', $Path, '-o', $chd)
    Safe-Cleanup $chd $logFile @($Path)
  } else {
    Warn "SKIP: Unsupported source for CHD: $Path"
    Add-Content -LiteralPath $logFile -Value ("[{0}] WARN: unsupported image type" -f (Now))
  }
}
#endregion

#region Main
Preflight

if ([string]::IsNullOrWhiteSpace($LogDir)) { $LogDir = Join-Path $RomDir '.chd_logs' }
Ensure-Dir $LogDir
Log "Per-title logs -> $LogDir"

if (-not [string]::IsNullOrWhiteSpace($OutDir)) {
  Log "Writing CHDs under OUT_DIR: $OutDir (mirroring structure from ROM_DIR)"
  Ensure-Dir $OutDir
}
if ($DryRun) { Warn "DRYRUN is ON — no files will be extracted, converted, or deleted." }

Log ("Starting ROMs -> CHD in: {0}  (JOBS={1}, RECURSIVE={2})" -f $RomDir, $Jobs, ([int]$Recursive.IsPresent))

$opt = @{ 'File'=$true; 'ErrorAction'='SilentlyContinue' }
$archives = Get-ChildItem -LiteralPath $RomDir -Include *.7z,*.zip -File -Recurse:$Recursive.IsPresent -ErrorAction SilentlyContinue
Log ("Archives found: {0}" -f ($archives | Measure-Object | Select-Object -ExpandProperty Count))

$cds  = Get-ChildItem -LiteralPath $RomDir -Include *.cue,*.gdi,*.toc -File -Recurse:$Recursive.IsPresent -ErrorAction SilentlyContinue
Log ("CD-like images found: {0}" -f ($cds | Measure-Object | Select-Object -ExpandProperty Count))
$dvds = Get-ChildItem -LiteralPath $RomDir -Include *.iso,*.gcm        -File -Recurse:$Recursive.IsPresent -ErrorAction SilentlyContinue
Log ("DVD-like images found: {0}" -f ($dvds | Measure-Object | Select-Object -ExpandProperty Count))

# Helper to run a list with parallelism
function Run-Parallel {
  param([System.Collections.IEnumerable]$Items, [scriptblock]$Action)

  if (-not $Items) { return }

  if ($PSVersionTable.PSVersion.Major -ge 7) {
    # Use ForEach-Object -Parallel
    $Items | ForEach-Object -Parallel $Action -ThrottleLimit $Jobs
  } else {
    # Fall back to Start-Job
    $jobs = @()
    foreach ($i in $Items) {
      $jobs += Start-Job -ScriptBlock $Action -ArgumentList $i
      while ($jobs.Count -ge $Jobs) {
        $done = Wait-Job -Job $jobs -Any
        $jobs = $jobs | Where-Object { $_.Id -ne $done.Id -and $_.State -eq 'Running' }
      }
    }
    if ($jobs.Count) { Wait-Job -Job $jobs | Out-Null }
    Receive-Job -Job $jobs | Out-Null
    Remove-Job -Job $jobs -Force -ErrorAction SilentlyContinue
  }
}

# Process archives first
if ($archives.Count -gt 0) {
  Run-Parallel -Items $archives -Action {
    param($a) 
    & $using:PSCommandPath Process-Archive $a.FullName
  }
} else {
  Warn "No archives found (.7z/.zip)."
}

# Then loose images
if ($cds.Count -gt 0) {
  Run-Parallel -Items $cds -Action {
    param($f)
    & $using:PSCommandPath Process-Loose $f.FullName
  }
}
if ($dvds.Count -gt 0) {
  Run-Parallel -Items $dvds -Action {
    param($f)
    & $using:PSCommandPath Process-Loose $f.FullName
  }
}

Ok "Done."
#endregion
