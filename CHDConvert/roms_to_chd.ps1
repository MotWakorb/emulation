<#
.SYNOPSIS
    Extract .7z archives and convert disc images (CUE/BIN, GDI, TOC, ISO/GCM) to CHD.

.DESCRIPTION
    - Optionally recurse through subfolders
    - Per-platform filtering (PSX, PS2, Dreamcast, GameCube, SegaCD, or All)
    - Uses 7-Zip for extraction and chdman for conversion
    - Analyzer-friendly (approved verbs only, no null-propagation operator, no $args assignment)

.PARAMETER SourceDir
    Directory to scan for .7z archives and disc images.

.PARAMETER OutputDir
    Where to place .chd files. Defaults to SourceDir.

.PARAMETER Platform
    Optional filter: PSX|PS2|Dreamcast|GC|SegaCD|All (default: All)

.PARAMETER Recurse
    Include subdirectories.

.PARAMETER KeepArchives
    Do not delete original .7z archives after successful extraction.

.PARAMETER KeepImages
    Do not delete original image files (cue/bin/gdi/toc/iso/gcm) after successful conversion.

.PARAMETER Force
    Overwrite existing .chd outputs.

.PARAMETER ChdmanPath
    Path to chdman executable. Defaults to 'chdman.exe' on PATH.

.PARAMETER SevenZipPath
    Path to 7-Zip CLI. Defaults to 'C:\Program Files\7-Zip\7z.exe'.

.PARAMETER MaxParallel
    Max concurrent conversions (1-8). Default: 2.

.PARAMETER LogDir
    Directory for logs. Defaults to script folder \logs.

.EXAMPLE
    .\roms_to_chd.ps1 -SourceDir "D:\ROMs\psx" -Platform PSX -Recurse -Force
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$SourceDir,

    [string]$OutputDir = $SourceDir,

    [ValidateSet('All','PSX','PS2','Dreamcast','GC','SegaCD')]
    [string]$Platform = 'All',

    [switch]$Recurse,
    [switch]$KeepArchives,
    [switch]$KeepImages,
    [switch]$Force,

    [string]$ChdmanPath = 'chdman.exe',
    [string]$SevenZipPath = 'C:\Program Files\7-Zip\7z.exe',

    [ValidateRange(1,8)]
    [int]$MaxParallel = 2,

    [string]$LogDir = (Join-Path -Path $PSScriptRoot -ChildPath 'logs')
)

# -------------------------
# Helpers (approved verbs)
# -------------------------

function Confirm-Directory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO','WARN','ERROR')]
        [string]$Level = 'INFO',
        [string]$Context = ''
    )
    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $prefix = if ($Context) { "[$Context] " } else { "" }
    $line = "$ts [$Level] ${prefix}$Message"
    Write-Host $line
    Add-Content -Path (Join-Path $LogDir 'roms_to_chd.log') -Value $line
}

function Test-CDImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    return @('.cue','.gdi','.toc') -contains $ext
}

function Test-DVDImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    return @('.iso','.gcm') -contains $ext
}

function Get-PrimaryDescriptorPath {
    <#
      For CD-based sets, prefer the descriptor file (.cue/.gdi/.toc) over .bin
      Returns $null if nothing suitable is found.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$AnyPathInSet)

    $dir = Split-Path -Path $AnyPathInSet -Parent
    $nameNoExt = [IO.Path]::GetFileNameWithoutExtension($AnyPathInSet)

    foreach ($ext in '.cue','.gdi','.toc') {
        $candidate = Join-Path $dir "$nameNoExt$ext"
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $first = Get-ChildItem -LiteralPath $dir -File -Include *.cue,*.gdi,*.toc -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $first) { return $first.FullName }

    return $null
}

function Test-PlatformMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [ValidateSet('All','Dreamcast','PS2','PSX','GC','SegaCD')]
        [string]$Platform
    )
    if ($Platform -eq 'All') { return $true }

    $ext = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    switch ($Platform) {
        'Dreamcast' { return @('.gdi','.toc') -contains $ext }
        'PS2'       { return @('.iso')        -contains $ext }
        'PSX'       { return @('.cue')        -contains $ext }
        'GC'        { return @('.gcm','.iso') -contains $ext }
        'SegaCD'    { return @('.cue')        -contains $ext }
    }
}

function Get-ChdOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputRoot
    )
    # Compute relative structure under SourceDir
    $fullIn = (Resolve-Path -LiteralPath $InputPath).Path
    $normSource = (Resolve-Path -LiteralPath $SourceDir).Path
    $rel = if ($fullIn.StartsWith($normSource, [System.StringComparison]::OrdinalIgnoreCase)) {
        $fullIn.Substring($normSource.Length).TrimStart('\','/')
    } else {
        [IO.Path]::GetFileName($fullIn)
    }

    $relDir = Split-Path -Path $rel -Parent
    $baseName = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    $destDir = if ($relDir) { Join-Path -Path $OutputRoot -ChildPath $relDir } else { $OutputRoot }
    Confirm-Directory $destDir
    return (Join-Path -Path $destDir -ChildPath "$baseName.chd")
}

function Get-ChdmanArgs {
    <#
      Returns: [string[]] args for chdman based on input format
      - CD-based: createcd -i <.cue/.gdi/.toc> -o <.chd>
      - DVD/GC ISO/GCM: createdvd -i <.iso/.gcm> -o <.chd>
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$OutputPath
    )
    $ext = [IO.Path]::GetExtension($InputPath).ToLowerInvariant()

    if (@('.cue','.gdi','.toc') -contains $ext) {
        return @('createcd','-i', $InputPath, '-o', $OutputPath)
    }

    if (@('.iso','.gcm') -contains $ext) {
        return @('createdvd','-i', $InputPath, '-o', $OutputPath)
    }

    return $null
}

function New-TempFilePath {
    # PowerShell 5.1-friendly temp file creator
    $tmp = [IO.Path]::GetTempFileName()
    return $tmp
}

function Invoke-External {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [Parameter(Mandatory)][string[]]$Arguments,
        [string]$LogContext = ''
    )
    $stdout = New-TempFilePath
    $stderr = New-TempFilePath

    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $FilePath
        # Quote args with whitespace
        $psi.Arguments = [string]::Join(' ', ($Arguments | ForEach-Object {
            if ($_ -match '\s') { '"{0}"' -f $_ } else { $_ }
        }))
        $psi.RedirectStandardError = $true
        $psi.RedirectStandardOutput = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = New-Object System.Diagnostics.Process
        $proc.StartInfo = $psi

        [void]$proc.Start()
        $out = $proc.StandardOutput.ReadToEnd()
        $err = $proc.StandardError.ReadToEnd()
        $proc.WaitForExit()

        Set-Content -LiteralPath $stdout -Value $out
        Set-Content -LiteralPath $stderr -Value $err

        if ($proc.ExitCode -ne 0) {
            Write-Log -Level 'ERROR' -Context $LogContext -Message ("ExitCode={0}`nSTDOUT:`n{1}`nSTDERR:`n{2}" -f $proc.ExitCode, $out, $err)
            return @{ Success=$false; ExitCode=$proc.ExitCode; StdOut=$out; StdErr=$err }
        }

        if ($out) { Write-Log -Level 'INFO' -Context $LogContext -Message $out.Trim() }
        if ($err) { Write-Log -Level 'WARN' -Context $LogContext -Message $err.Trim() }

        return @{ Success=$true; ExitCode=$proc.ExitCode; StdOut=$out; StdErr=$err }
    }
    catch {
        $eMsg = $_.Exception.Message
        $eSrc = if ($_.Exception) { $_.Exception.Source } else { $null }
        Write-Log -Level 'ERROR' -Context $LogContext -Message "Failed to run '$FilePath': $eMsg (Source=$eSrc)"
        return @{ Success=$false; ExitCode=-1; StdOut=''; StdErr=$eMsg }
    }
    finally {
        # Remove temp files
        Remove-Item -LiteralPath $stdout,$stderr -ErrorAction SilentlyContinue
    }
}

function Expand-SevenZipArchive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationDir
    )
    Confirm-Directory $DestinationDir
    $ctx = "7z: $(Split-Path -Path $ArchivePath -Leaf)"
    $sevenZipArgs = @('x', '-y', '-o' + $DestinationDir, $ArchivePath)

    if (-not (Test-Path -LiteralPath $SevenZipPath)) {
        throw "7-Zip CLI not found: '$SevenZipPath'"
    }

    $res = Invoke-External -FilePath $SevenZipPath -Arguments $sevenZipArgs -LogContext $ctx
    return $res.Success
}

# -------------------------
# Begin
# -------------------------

try {
    Confirm-Directory $SourceDir
    Confirm-Directory $OutputDir
    Confirm-Directory $LogDir

    Write-Log "Starting scan. Source='$SourceDir' Output='$OutputDir' Platform='$Platform' Recurse=$($Recurse.IsPresent) Force=$($Force.IsPresent) MaxParallel=$MaxParallel"

    # 1) Extract *.7z into same folder
    $archiveQuery = @{
        LiteralPath = $SourceDir
        File        = $true
        Include     = @('*.7z')
        ErrorAction = 'SilentlyContinue'
    }
    if ($Recurse) { $archiveQuery.Recurse = $true }
    $archives = Get-ChildItem @archiveQuery

    foreach ($a in $archives) {
        $dest = $a.DirectoryName
        Write-Log -Message "Extracting archive: $($a.FullName) -> $dest"
        $ok = $false
        try {
            $ok = Expand-SevenZipArchive -ArchivePath $a.FullName -DestinationDir $dest
        }
        catch {
            $msg = $_.Exception.Message
            $src = if ($_.Exception) { $_.Exception.Source } else { $null }
            Write-Log -Level 'ERROR' -Message "Extraction failed for '$($a.FullName)': $msg (Source=$src)"
        }

        if ($ok -and -not $KeepArchives) {
            try {
                Remove-Item -LiteralPath $a.FullName -Force
                Write-Log "Deleted archive: $($a.FullName)"
            }
            catch {
                Write-Log -Level 'WARN' -Message "Could not delete archive '$($a.FullName)': $($_.Exception.Message)"
            }
        }
    }

    # 2) Find candidate images
    $imgQuery = @{
        LiteralPath = $SourceDir
        File        = $true
        Include     = @('*.cue','*.gdi','*.toc','*.iso','*.gcm')
        ErrorAction = 'SilentlyContinue'
    }
    if ($Recurse) { $imgQuery.Recurse = $true }
    $files = Get-ChildItem @imgQuery

    # Filter by platform intent
    $candidates = $files | Where-Object { Test-PlatformMatch -Path $_.FullName -Platform $Platform }

    if (-not $candidates) {
        Write-Log -Level 'WARN' -Message "No matching disc images found for Platform='$Platform'."
        return
    }

    Write-Log "Found $($candidates.Count) candidate image(s). Beginning conversion…"

    # Parallel gate
    $sem = New-Object System.Threading.SemaphoreSlim($MaxParallel, $MaxParallel)
    $tasks = New-Object System.Collections.Generic.List[System.Threading.Tasks.Task]

    foreach ($f in $candidates) {
        # capture per-iteration values
        $inPathCaptured = $f.FullName
        $null = $sem.Wait()
        $task = [Threading.Tasks.Task]::Run({
            try {
                $inPath = $inPathCaptured
                $ctx = "CHDMAN: " + (Split-Path -Path $inPath -Leaf)

                # For CD-based sets, ensure we feed descriptor (cue/gdi/toc) to chdman
                $inputForChd = $inPath
                $ext = [IO.Path]::GetExtension($inPath).ToLowerInvariant()
                if (@('.bin') -contains $ext) {
                    $desc = Get-PrimaryDescriptorPath -AnyPathInSet $inPath
                    if ($null -ne $desc) { $inputForChd = $desc }
                } elseif (@('.cue','.gdi','.toc') -notcontains $ext) {
                    # If it's not a descriptor and not ISO/GCM, try to find a descriptor neighbor
                    $desc = Get-PrimaryDescriptorPath -AnyPathInSet $inPath
                    if ($null -ne $desc) { $inputForChd = $desc }
                }

                $outPath = Get-ChdOutputPath -InputPath $inputForChd -OutputRoot $OutputDir
                if ((Test-Path -LiteralPath $outPath) -and (-not $Force)) {
                    Write-Log -Level 'WARN' -Context $ctx -Message "Output exists, skipping: $outPath (use -Force to overwrite)"
                    return
                }

                $argsForChd = Get-ChdmanArgs -InputPath $inputForChd -OutputPath $outPath
                if ($null -eq $argsForChd) {
                    Write-Log -Level 'WARN' -Context $ctx -Message "Unsupported input type for '$inputForChd' — skipping."
                    return
                }

                if (-not (Test-Path -LiteralPath $ChdmanPath)) {
                    Write-Log -Level 'ERROR' -Context $ctx -Message "chdman not found: '$ChdmanPath'"
                    return
                }

                Write-Log -Context $ctx -Message ("Converting -> {0}" -f $outPath)
                $res = Invoke-External -FilePath $ChdmanPath -Arguments $argsForChd -LogContext $ctx
                if (-not $res.Success) { return }

                # Post-conversion cleanup
                if (-not $KeepImages) {
                    try {
                        $toRemove = @()

                        switch -Regex ([regex]::Escape([IO.Path]::GetExtension($inputForChd).ToLowerInvariant())) {
                            '\.cue' {
                                $dir = Split-Path -Path $inputForChd -Parent
                                $base = [IO.Path]::GetFileNameWithoutExtension($inputForChd)
                                $toRemove += $inputForChd
                                $toRemove += Get-ChildItem -LiteralPath $dir -File -Filter "$base*.bin" -ErrorAction SilentlyContinue | ForEach-Object FullName
                            }
                            '\.gdi' {
                                $dir = Split-Path -Path $inputForChd -Parent
                                $base = [IO.Path]::GetFileNameWithoutExtension($inputForChd)
                                $toRemove += $inputForChd
                                $toRemove += Get-ChildItem -LiteralPath $dir -File -Filter "$base*.bin" -ErrorAction SilentlyContinue | ForEach-Object FullName
                            }
                            '\.toc' {
                                $dir = Split-Path -Path $inputForChd -Parent
                                $base = [IO.Path]::GetFileNameWithoutExtension($inputForChd)
                                $toRemove += $inputForChd
                                $toRemove += Get-ChildItem -LiteralPath $dir -File -Filter "$base*.bin" -ErrorAction SilentlyContinue | ForEach-Object FullName
                            }
                            '\.iso' { $toRemove += $inputForChd }
                            '\.gcm' { $toRemove += $inputForChd }
                            default { $toRemove += $inputForChd }
                        }

                        $toRemove = $toRemove | Sort-Object -Unique
                        foreach ($p in $toRemove) {
                            if (Test-Path -LiteralPath $p) {
                                Remove-Item -LiteralPath $p -Force
                                Write-Log -Context $ctx -Message "Deleted source: $p"
                            }
                        }
                    }
                    catch {
                        Write-Log -Level 'WARN' -Context $ctx -Message "Post-conversion cleanup failed: $($_.Exception.Message)"
                    }
                }
            }
            finally {
                $sem.Release() | Out-Null
            }
        })
        $tasks.Add($task) | Out-Null
    }

    if ($tasks.Count -gt 0) {
        [Threading.Tasks.Task]::WaitAll($tasks.ToArray())
    }
    Write-Log "All done."
}
catch {
    $msg = $_.Exception.Message
    $src = if ($_.Exception) { $_.Exception.Source } else { $null }
    Write-Log -Level 'ERROR' -Message "Fatal error: $msg (Source=$src)"
    throw
}