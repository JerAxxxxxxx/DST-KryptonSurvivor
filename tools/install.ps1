param(
    [string]$GameDir = $(if ($env:DST_GAME_DIR) { $env:DST_GAME_DIR } else { "D:\SteamLibrary\steamapps\common\Don't Starve Together" })
)
$ErrorActionPreference = 'Stop'
$runningGame = Get-Process -Name 'dontstarve*' -ErrorAction SilentlyContinue
if ($runningGame) { throw 'Exit the game and dedicated server before installing the mod.' }
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$gameRoot = (Resolve-Path -LiteralPath $GameDir).Path
$modsRoot = [System.IO.Path]::GetFullPath((Join-Path $gameRoot 'mods'))
$installRoot = [System.IO.Path]::GetFullPath((Join-Path $modsRoot 'KryptonSurvivor'))
$sourceRoot = Join-Path $projectRoot 'mod'
$archiveRoot = Join-Path $projectRoot 'archive'
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
$stageRoot = Join-Path $modsRoot ('.krypton-stage-' + $stamp)
$backupRoot = Join-Path $archiveRoot ('installed-before-' + $stamp)

function Assert-ChildPath($Path, $Parent) {
    $full = [System.IO.Path]::GetFullPath($Path)
    if (!$full.StartsWith([System.IO.Path]::GetFullPath($Parent).TrimEnd('\') + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Unsafe target: $Path"
    }
}
function Assert-NoLinks($Path) {
    if (!(Test-Path -LiteralPath $Path)) { return }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw "Links are not supported: $Path" }
    if ($item.PSIsContainer) {
        foreach ($child in Get-ChildItem -LiteralPath $Path -Force) { Assert-NoLinks $child.FullName }
    }
}
function Assert-MatchesSource($Target) {
    $sourceFiles = @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force)
    $targetFiles = @(Get-ChildItem -LiteralPath $Target -File -Recurse -Force)
    if ($sourceFiles.Count -ne $targetFiles.Count) { throw 'Installed file list differs from source.' }
    foreach ($file in $sourceFiles) {
        $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $file.FullName)
        $targetFile = Join-Path $Target $relative
        if (!(Test-Path -LiteralPath $targetFile -PathType Leaf) -or
            (Get-FileHash -LiteralPath $file.FullName).Hash -ne (Get-FileHash -LiteralPath $targetFile).Hash) {
            throw "Installed file differs: $relative"
        }
    }
    return $sourceFiles.Count
}
Assert-ChildPath $installRoot $modsRoot
Assert-ChildPath $stageRoot $modsRoot
Assert-ChildPath $backupRoot $archiveRoot
# Reject linked ancestors too, before copying or moving any directory.
for ($ancestor = Get-Item -LiteralPath $gameRoot; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
    if ($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Game path must not pass through a link.' }
}
if ((Test-Path -LiteralPath $modsRoot) -and ((Get-Item -LiteralPath $modsRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    throw 'Mods directory must not be a link.'
}
Assert-NoLinks $sourceRoot
Assert-NoLinks $installRoot
# Equality with a damaged/empty source is not a valid installation.
# Fail before creating staging data or moving the working installation.
foreach ($entryPoint in @('modinfo.lua', 'modmain.lua')) {
    $entryPath = Join-Path $sourceRoot $entryPoint
    if (!(Test-Path -LiteralPath $entryPath -PathType Leaf) -or (Get-Item -LiteralPath $entryPath).Length -eq 0) {
        throw "Missing or empty mod entry point: $entryPoint"
    }
}
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
for ($ancestor = Get-Item -LiteralPath $archiveRoot; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
    if ($ancestor.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { throw 'Archive path must not pass through a link.' }
}
New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
$oldMoved = $false
$newMoved = $false
try {
    Get-ChildItem -LiteralPath $sourceRoot -Force | Copy-Item -Destination $stageRoot -Recurse -Force
    $verified = Assert-MatchesSource $stageRoot
    if (Test-Path -LiteralPath $installRoot) {
        Move-Item -LiteralPath $installRoot -Destination $backupRoot
        $oldMoved = $true
        Write-Output "Backup (including local extra files): $backupRoot"
    }
    Move-Item -LiteralPath $stageRoot -Destination $installRoot
    $newMoved = $true
    $verified = Assert-MatchesSource $installRoot
} catch {
    # Preserve a failed new install for diagnosis, then restore the old one.
    if ($newMoved) {
        $failedRoot = Join-Path $archiveRoot ('failed-install-' + $stamp)
        Assert-ChildPath $failedRoot $archiveRoot
        Move-Item -LiteralPath $installRoot -Destination $failedRoot
    }
    if ($oldMoved) { Move-Item -LiteralPath $backupRoot -Destination $installRoot }
    throw
} finally {
    if (Test-Path -LiteralPath $stageRoot) {
        Assert-ChildPath $stageRoot $modsRoot
        Remove-Item -LiteralPath $stageRoot -Recurse -Force
    }
}
Write-Output "Installed and verified $verified files: $installRoot"
