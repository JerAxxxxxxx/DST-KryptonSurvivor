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
if (!$installRoot.StartsWith($modsRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid installation target.' }
if ((Test-Path -LiteralPath $installRoot) -and ((Get-Item -LiteralPath $installRoot).Attributes -band [System.IO.FileAttributes]::ReparsePoint)) {
    throw 'Installation target must not be a junction or symlink.'
}
$sourceRoot = Join-Path $projectRoot 'mod'
$archiveRoot = Join-Path $projectRoot 'archive'
New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
if (Test-Path -LiteralPath $installRoot) {
    $snapshotPath = Join-Path $archiveRoot ('installed-before-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    Compress-Archive -Path (Join-Path $installRoot '*') -DestinationPath $snapshotPath
    Write-Output ("Backup: " + $snapshotPath)
}
New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
Copy-Item -Path (Join-Path $sourceRoot '*') -Destination $installRoot -Recurse -Force
$verified = 0
foreach ($sourceFile in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) {
    $relative = [System.IO.Path]::GetRelativePath($sourceRoot, $sourceFile.FullName)
    $target = Join-Path $installRoot $relative
    if ((Get-FileHash -LiteralPath $sourceFile.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash) {
        throw ("Installed file differs: " + $relative)
    }
    $verified++
}
Write-Output ("Installed and verified " + $verified + " files: " + $installRoot)
