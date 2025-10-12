param(
  [Parameter(Mandatory=$true)][string]$RomDir,
  [string]$OutDir,
  [string]$LogDir,
  [switch]$Recurse,
  [int]$Jobs = 4,
  [switch]$DryRun,
  [switch]$Force,
  [switch]$KeepArchives,
  [ValidateSet('Dreamcast','PS2','PSX','GC')][string]$OnlyPlatform
)

# Requires PowerShell 7+ for -Parallel
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Timestamp { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
function Write-Info([string]$msg){ Write-Host "[{0}] {1}" -f (Timestamp), $msg -ForegroundColor Cyan }
function Write-Ok  ([string]$msg){ Write-Host "[{0}] {1}" -f (Timestamp), $msg -ForegroundColor Green }
function Write-Warn([string]$msg){ Write-Host "[{0}] {1}" -f (Timestamp), $msg -ForegroundColor Yellow }
function Write-Err ([string]$msg){ Write-Host "[{0}] {1}" -f (Timestamp), $msg -ForegroundColor Red }

if (-not (Test-Path -LiteralPath $RomDir -PathType Container)) {
  Write-Err "ROM directory not found: $RomDir"; exit 2
}

if (-not $LogDir) { $LogDir = Join-Path $RomDir '.chd_logs' }
if (-not $OutDir) { $OutDir = $RomDir }
if (-not (Test-Path -LiteralPath $LogDir)) { New-Item -ItemType Directory -Force -Path $LogDir | Out-Null }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Force -Path $OutDir | Out-Null }

function Resolve-7z {
  $cands = @('7zz.exe','7z.exe')
  foreach($c in $cands){
    $p = (Get-Command $c -ErrorAction SilentlyContinue)?.Source
    if ($p) { return $p }
  }
  return $null
}

$SevenZip = Resolve-7z
$Chdman   = (Get-Command 'chdman.exe' -ErrorAction SilentlyContinue)?.Source
if (-not $SevenZip) { Write-Err "Missing 7-Zip CLI (7z/7zz) on PATH."; exit 2 }
if (-not $Chdman)   { Write-Err "Missing chdman.exe (from MAME) on PATH."; exit 2 }

Write-Ok "Preflight OK: using $(Split-Path -Leaf $SevenZip) and $(Split-Path -Leaf $Chdman)."

function SanitizeName([string]$name){
  $invalid = [System.IO.Path]::GetInvalidFileNameChars()
  foreach($ch in $invalid){ $name = $name -replace [Regex]::Escape([string]$ch), '_' }
  return $name
}

function Get-DestDir([string]$srcDir){
  $rom = (Resolve-Path -LiteralPath $RomDir).Path
  $out = (Resolve-Path -LiteralPath $OutDir).Path
  $src = (Resolve-Path -LiteralPath $srcDir).Path
  if ($src -eq $rom) { return $out }
  if ($src.StartsWith($rom, [System.StringComparison]::OrdinalIgnoreCase)){
    $rel = $src.Substring($rom.Length).TrimStart('\','/')
    return (Join-Path $out $rel)
  }
  return $out
}

$DVD_EXTS = @('.iso','.gcm')
$CD_EXTS  = @('.cue','.gdi','.toc')

function Is-CD([string]$path){ $ext = [IO.Path]::GetExtension($path).ToLowerInvariant(); return $CD_EXTS -contains $ext }
function Is-DVD([string]$path){ $ext = [IO.Path]::GetExtension($path).ToLowerInvariant(); return $DVD_EXTS -contains $ext }

function Accept-ByPlatform([string]$path){
  if (-not $OnlyPlatform) { return $true }
  $ext = [IO.Path]::GetExtension($path).ToLowerInvariant()
  switch ($OnlyPlatform){
    'Dreamcast' { return @('.gdi','.toc') -contains $ext } # avoid .cue overlap with PSX
    'PS2'       { return @('.iso')       -contains $ext }
    'PSX'       { return @('.cue')       -contains $ext }
    'GC'        { return @('.gcm','.iso')-contains $ext }
  }
  return $true
}

function Get-CueTracks([string]$cuePath){
  $dir = Split-Path -LiteralPath $cuePath -Parent
  $list = @()
  Get-Content -LiteralPath $cuePath | ForEach-Object {
    $line = $_.Trim()
    if ($line -match '^(?i)FILE\s+"([^"]+)"'){
      $f = $Matches[1]
      $full = Join-Path $dir $f
      if (Test-Path -LiteralPath $full) { $list += $full }
    }
  }
  return $list
}

function Ensure-Dir([string]$path){
  if ($DryRun) { Write-Info "DRYRUN: mkdir -p -- $path" }
  else { New-Item -ItemType Directory -Force -Path $path | Out-Null }
}

$searchOpt = @()
if ($Recurse){ $searchOpt += '-Recurse' }

$archives = Get-ChildItem -LiteralPath $RomDir -File @searchOpt |
  Where-Object { $_.Extension -match '^\.(zip|7z)$' }

$images = Get-ChildItem -LiteralPath $RomDir -File @searchOpt |
  Where-Object { $_.Extension -match '^\.(cue|gdi|toc|iso|gcm|cdi)$' }

Write-Info "Archives found: $($archives.Count)"
Write-Info "Loose images found: $($images.Count)"

$Results = New-Object System.Collections.Concurrent.ConcurrentBag[object]

$archives | ForEach-Object -Parallel {
  param($SevenZip,$Chdman,$RomDir,$OutDir,$LogDir,$DryRun,$Force,$KeepArchives,$OnlyPlatform,$Results)

  function Timestamp { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
  function LogLine([string]$lf,[string]$text){ Add-Content -LiteralPath $lf -Value ("[{0}] {1}" -f (Timestamp), $text) }
  function Accept-ByPlatform([string]$p){
    if (-not $OnlyPlatform) { return $true }
    $ext = [IO.Path]::GetExtension($p).ToLowerInvariant()
    switch ($OnlyPlatform){
      'Dreamcast' { return @('.gdi','.toc') -contains $ext }
      'PS2'       { return @('.iso')        -contains $ext }
      'PSX'       { return @('.cue')        -contains $ext }
      'GC'        { return @('.gcm','.iso') -contains $ext }
    }
    return $true
  }
  function Get-CueTracks([string]$cuePath){
    $dir = Split-Path -LiteralPath $cuePath -Parent
    $list = @()
    Get-Content -LiteralPath $cuePath | ForEach-Object {
      $line = $_.Trim()
      if ($line -match '^(?i)FILE\s+"([^"]+)"'){
        $f = $Matches[1]
        $full = Join-Path $dir $f
        if (Test-Path -LiteralPath $full) { $list += $full }
      }
    }
    return $list
  }
  function DestDir([string]$srcDir){
    $rom = (Resolve-Path -LiteralPath $RomDir).Path
    $out = (Resolve-Path -LiteralPath $OutDir).Path
    $src = (Resolve-Path -LiteralPath $srcDir).Path
    if ($src -eq $rom) { return $out }
    if ($src.StartsWith($rom, [System.StringComparison]::OrdinalIgnoreCase)){
      $rel = $src.Substring($rom.Length).TrimStart('\','/')
      return (Join-Path $out $rel)
    }
    return $out
  }

  $arc = $_.FullName
  $name = $_.BaseName
  $logf = Join-Path $LogDir ("{0}.log" -f $name)
  "Title: $name`nSource: $arc`n" | Set-Content -LiteralPath $logf

  $outChd = Join-Path (DestDir $_.DirectoryName) ("{0}.chd" -f $name)
  if ((Test-Path -LiteralPath $outChd) -and (-not $Force)) {
    LogLine $logf "SKIP: CHD exists: $outChd"
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='EXIST'})
    return
  }

  if ($DryRun){
    LogLine $logf "DRYRUN: extract `"$arc`""
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='WOULD'})
    return
  }

  $tmp = Join-Path $_.DirectoryName (".extract_{0}_{1}" -f $name, [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $tmp | Out-Null
  $args = @('x','-y',("-o{0}" -f $tmp), $arc)
  $p = Start-Process -FilePath $SevenZip -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logf -RedirectStandardError $logf
  if ($p.ExitCode -ne 0){
    LogLine $logf "ERROR: extraction failed"
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
    Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
    return
  }

  $desc = Get-ChildItem -LiteralPath $tmp -File | Where-Object { $_.Extension -match '^\.(gdi|toc|cue)$' } | Select-Object -First 1
  $dvd  = Get-ChildItem -LiteralPath $tmp -File | Where-Object { $_.Extension -match '^\.(iso|gcm)$' } | Select-Object -First 1
  $cdi  = Get-ChildItem -LiteralPath $tmp -File | Where-Object { $_.Extension -ieq '.cdi' } | Select-Object -First 1

  if ($desc -and -not (Accept-ByPlatform $desc.FullName)) { $desc = $null }
  if ($dvd  -and -not (Accept-ByPlatform $dvd.FullName))  { $dvd = $null }

  if ($desc){
    $force = @(); if ($Force){ $force = @('-f') }
    $args = @('createcd') + $force + @('-i',$desc.FullName,'-o',$outChd)
    $rc = (Start-Process -FilePath $Chdman -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logf -RedirectStandardError $logf).ExitCode
    if ($rc -eq 0){
      $tracks = if ($desc.Extension -ieq '.cue'){ Get-CueTracks $desc.FullName } else { @() }
      if (Test-Path -LiteralPath $outChd -PathType Leaf){
        foreach($s in @($desc.FullName) + $tracks){ Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue }
        if (-not $KeepArchives){ Remove-Item -LiteralPath $arc -Force -ErrorAction SilentlyContinue }
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='OK'})
      } else {
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
      }
    } else {
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
    }
  }
  elseif ($dvd){
    $force = @(); if ($Force){ $force = @('-f') }
    $args = @('createdvd') + $force + @('-i',$dvd.FullName,'-o',$outChd)
    $rc = (Start-Process -FilePath $Chdman -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logf -RedirectStandardError $logf).ExitCode
    if ($rc -eq 0){
      if (Test-Path -LiteralPath $outChd -PathType Leaf){
        Remove-Item -LiteralPath $dvd.FullName -Force -ErrorAction SilentlyContinue
        if (-not $KeepArchives){ Remove-Item -LiteralPath $arc -Force -ErrorAction SilentlyContinue }
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='OK'})
      } else {
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
      }
    } else {
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
    }
  }
  elseif ($cdi){
    LogLine $logf "WARN: .cdi not supported by chdman; convert to GDI or CUE/BIN first."
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='WARN_CDI'})
  }
  else{
    LogLine $logf "No convertible image found in archive."
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='SKIP'})
  }

  Remove-Item -Recurse -Force -LiteralPath $tmp -ErrorAction SilentlyContinue
} -ThrottleLimit $Jobs -ArgumentList $SevenZip,$Chdman,$RomDir,$OutDir,$LogDir,$DryRun.IsPresent,$Force.IsPresent,$KeepArchives.IsPresent,$OnlyPlatform,$Results

$images | ForEach-Object -Parallel {
  param($Chdman,$RomDir,$OutDir,$LogDir,$DryRun,$Force,$OnlyPlatform,$Results)

  function Timestamp { Get-Date -Format 'yyyy-MM-dd HH:mm:ss' }
  function LogLine([string]$lf,[string]$text){ Add-Content -LiteralPath $lf -Value ("[{0}] {1}" -f (Timestamp), $text) }
  function Accept-ByPlatform([string]$p){
    if (-not $OnlyPlatform) { return $true }
    $ext = [IO.Path]::GetExtension($p).ToLowerInvariant()
    switch ($OnlyPlatform){
      'Dreamcast' { return @('.gdi','.toc') -contains $ext }
      'PS2'       { return @('.iso')        -contains $ext }
      'PSX'       { return @('.cue')        -contains $ext }
      'GC'        { return @('.gcm','.iso') -contains $ext }
    }
    return $true
  }
  function Get-CueTracks([string]$cuePath){
    $dir = Split-Path -LiteralPath $cuePath -Parent
    $list = @()
    Get-Content -LiteralPath $cuePath | ForEach-Object {
      $line = $_.Trim()
      if ($line -match '^(?i)FILE\s+"([^"]+)"'){
        $f = $Matches[1]
        $full = Join-Path $dir $f
        if (Test-Path -LiteralPath $full) { $list += $full }
      }
    }
    return $list
  }
  function DestDir([string]$srcDir){
    $rom = (Resolve-Path -LiteralPath $RomDir).Path
    $out = (Resolve-Path -LiteralPath $OutDir).Path
    $src = (Resolve-Path -LiteralPath $srcDir).Path
    if ($src -eq $rom) { return $out }
    if ($src.StartsWith($rom, [System.StringComparison]::OrdinalIgnoreCase)){
      $rel = $src.Substring($rom.Length).TrimStart('\','/')
      return (Join-Path $out $rel)
    }
    return $out
  }

  $f = $_.FullName
  if (-not (Accept-ByPlatform $f)){
    $name = $_.BaseName
    $logf = Join-Path $LogDir ("{0}.log" -f $name)
    "Title: $name`nSource: $f`n" | Set-Content -LiteralPath $logf
    LogLine $logf "SKIP: filtered by --OnlyPlatform"
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='SKIP'})
    return
  }

  $name = $_.BaseName
  $logf = Join-Path $LogDir ("{0}.log" -f $name)
  "Title: $name`nSource: $f`n" | Set-Content -LiteralPath $logf

  $destDir = DestDir $_.DirectoryName
  if ($DryRun){
    Add-Content -LiteralPath $logf -Value ("[{0}] DRYRUN: ensure out dir {1}" -f (Timestamp), $destDir)
  } else {
    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
  }

  $outChd = Join-Path $destDir ("{0}.chd" -f $name)
  if ((Test-Path -LiteralPath $outChd) -and (-not $Force)){
    LogLine $logf "SKIP: CHD exists: $outChd"
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='EXIST'})
    return
  }

  $ext = $_.Extension.ToLowerInvariant()
  if ($ext -in @('.cue','.gdi','.toc')){
    if ($DryRun){
      LogLine $logf "DRYRUN: chdman createcd -i `"$f`" -o `"$outChd`""
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='WOULD'})
      return
    }
    $force = @(); if ($Force){ $force = @('-f') }
    $args = @('createcd') + $force + @('-i',$f,'-o',$outChd)
    $rc = (Start-Process -FilePath $Chdman -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logf -RedirectStandardError $logf).ExitCode
    if ($rc -eq 0){
      $tracks = if ($ext -eq '.cue'){ Get-CueTracks $f } else { @() }
      if (Test-Path -LiteralPath $outChd -PathType Leaf){
        foreach($s in @($f) + $tracks){ Remove-Item -LiteralPath $s -Force -ErrorAction SilentlyContinue }
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='OK'})
      } else {
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
      }
    } else {
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
    }
  }
  elseif ($ext -in @('.iso','.gcm')){
    if ($DryRun){
      LogLine $logf "DRYRUN: chdman createdvd -i `"$f`" -o `"$outChd`""
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='WOULD'})
      return
    }
    $force = @(); if ($Force){ $force = @('-f') }
    $args = @('createdvd') + $force + @('-i',$f,'-o',$outChd)
    $rc = (Start-Process -FilePath $Chdman -ArgumentList $args -NoNewWindow -PassThru -Wait -RedirectStandardOutput $logf -RedirectStandardError $logf).ExitCode
    if ($rc -eq 0){
      if (Test-Path -LiteralPath $outChd -PathType Leaf){
        Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='OK'})
      } else {
        [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
      }
    } else {
      [void]$Results.Add([pscustomobject]@{Title=$name; Status='FAIL'})
    }
  }
  elseif ($ext -eq '.cdi'){
    LogLine $logf "WARN: .cdi not supported by chdman; convert to GDI or CUE/BIN first."
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='WARN_CDI'})
  }
  else{
    LogLine $logf "Unsupported image type: $ext"
    [void]$Results.Add([pscustomobject]@{Title=$name; Status='SKIP'})
  }
} -ThrottleLimit $Jobs -ArgumentList $Chdman,$RomDir,$OutDir,$LogDir,$DryRun.IsPresent,$Force.IsPresent,$OnlyPlatform,$Results

# Summary
$groups = $Results | Group-Object -Property Status
$total = ($Results | Measure-Object).Count
Write-Host ""
Write-Info "Summary:"
Write-Host ("  Total items: {0}" -f $total)
foreach($k in @('OK','FAIL','SKIP','EXIST','WARN_CDI','WOULD')){
  $n = ($groups | Where-Object Name -EQ $k | Select-Object -ExpandProperty Count -ErrorAction SilentlyContinue)
  if (-not $n) { $n = 0 }
  Write-Host ("    {0,-10} {1}" -f ($k+':'), $n)
}
