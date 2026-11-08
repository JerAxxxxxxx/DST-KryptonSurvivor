param()
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modRoot = Join-Path $projectRoot 'mod'
$distRoot = Join-Path $projectRoot 'dist'
New-Item -ItemType Directory -Path $distRoot -Force | Out-Null
$info = Get-Content -LiteralPath (Join-Path $modRoot 'modinfo.lua') -Raw
if ($info -notmatch 'version\s*=\s*"([0-9.]+)"') { throw 'Mod version was not found.' }
$destination = Join-Path $distRoot ("KryptonSurvivor-{0}.zip" -f $Matches[1])
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N')
$temporary = Join-Path $distRoot ('.package-' + $stamp + '.zip')
try {
    Compress-Archive -Path (Join-Path $modRoot '*') -DestinationPath $temporary
    if (Test-Path -LiteralPath $destination) {
        $archiveRoot = Join-Path $projectRoot 'archive/packages'
        New-Item -ItemType Directory -Path $archiveRoot -Force | Out-Null
        $backup = Join-Path $archiveRoot (([System.IO.Path]::GetFileNameWithoutExtension($destination)) + '-' + $stamp + '.zip')
        Copy-Item -LiteralPath $destination -Destination $backup
        if ((Get-FileHash -LiteralPath $destination).Hash -ne (Get-FileHash -LiteralPath $backup).Hash) {
            throw 'Package backup verification failed.'
        }
        Write-Output "Previous package: $backup"
    }
    Move-Item -LiteralPath $temporary -Destination $destination -Force
} finally {
    if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary }
}
Write-Output $destination
