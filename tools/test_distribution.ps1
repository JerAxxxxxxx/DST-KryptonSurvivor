# Run in PowerShell 7. Fixtures stay under ignored build/; no real game is modified.
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$fixture = Join-Path $projectRoot ('build/distribution-test-' + [guid]::NewGuid().ToString('N'))
$fixtureTools = Join-Path $fixture 'tools'
$game = Join-Path $fixture 'game'
$installed = Join-Path $game 'mods/KryptonSurvivor'
New-Item -ItemType Directory -Path $fixtureTools,(Join-Path $fixture 'mod/scripts'),$installed -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'install.ps1'),(Join-Path $PSScriptRoot 'package.ps1') -Destination $fixtureTools
Set-Content -LiteralPath (Join-Path $fixture 'mod/modinfo.lua') -Value 'version = "0.0.1"'
Set-Content -LiteralPath (Join-Path $fixture 'mod/modmain.lua') -Value '-- test mod'
Set-Content -LiteralPath (Join-Path $fixture 'mod/scripts/new.lua') -Value 'return 1'
Set-Content -LiteralPath (Join-Path $installed 'obsolete.lua') -Value 'old script'
Set-Content -LiteralPath (Join-Path $installed 'local-note.txt') -Value 'keep me'
& (Join-Path $fixtureTools 'install.ps1') -GameDir $game
if (Test-Path -LiteralPath (Join-Path $installed 'obsolete.lua')) { throw 'Stale script survived installation.' }
$backup = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'archive') -Directory)[0].FullName
if ((Get-Content -LiteralPath (Join-Path $backup 'local-note.txt') -Raw).Trim() -ne 'keep me') { throw 'Local extra file was lost.' }

# A source missing its runtime entry point must leave the installed copy alone.
$entry = Join-Path $fixture 'mod/modmain.lua'
$entryText = Get-Content -LiteralPath $entry -Raw
Set-Content -LiteralPath $entry -Value '' -NoNewline
$rejected = $false
try { & (Join-Path $fixtureTools 'install.ps1') -GameDir $game } catch {
    if ($_.Exception.Message -notlike '*Missing or empty mod entry point*') { throw }
    $rejected = $true
} finally { Set-Content -LiteralPath $entry -Value $entryText -NoNewline }
if (!$rejected -or !(Test-Path -LiteralPath (Join-Path $installed 'scripts/new.lua'))) { throw 'Invalid source was not rejected safely.' }

# Inject a failure after moving the old install, before activating the new one.
$before = (Get-FileHash -LiteralPath (Join-Path $installed 'scripts/new.lua')).Hash
Set-Content -LiteralPath (Join-Path $fixture 'mod/scripts/new.lua') -Value 'return 2'
function Move-Item {
    param($LiteralPath, $Destination)
    if ([IO.Path]::GetFileName($LiteralPath).StartsWith('.krypton-stage-')) { throw 'Injected activation failure' }
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
}
$failed = $false
try { & (Join-Path $fixtureTools 'install.ps1') -GameDir $game } catch {
    if ($_.Exception.Message -notlike '*Injected activation failure*') { throw }
    $failed = $true
} finally { Remove-Item Function:\Move-Item }
if (!$failed -or (Get-FileHash -LiteralPath (Join-Path $installed 'scripts/new.lua')).Hash -ne $before) {
    throw 'Failed installation did not restore the old content.'
}
if (@(Get-ChildItem -LiteralPath (Join-Path $game 'mods') -Force | Where-Object Name -Like '.krypton-stage-*').Count -ne 0) {
    throw 'Staging directory survived cleanup.'
}
& (Join-Path $fixtureTools 'install.ps1') -GameDir $game
if ((Get-Content -LiteralPath (Join-Path $installed 'scripts/new.lua') -Raw).Trim() -ne 'return 2') { throw 'Retry failed.' }
# Damage the newly activated copy to exercise post-activation verification.
function Move-Item {
    param($LiteralPath, $Destination)
    Microsoft.PowerShell.Management\Move-Item -LiteralPath $LiteralPath -Destination $Destination
    if ([IO.Path]::GetFileName($LiteralPath).StartsWith('.krypton-stage-')) {
        Set-Content -LiteralPath (Join-Path $Destination 'scripts/new.lua') -Value 'corrupted'
    }
}
$failed = $false
try { & (Join-Path $fixtureTools 'install.ps1') -GameDir $game } catch {
    if ($_.Exception.Message -notlike '*Installed file differs*') { throw }
    $failed = $true
} finally { Remove-Item Function:\Move-Item }
if (!$failed -or (Get-Content -LiteralPath (Join-Path $installed 'scripts/new.lua') -Raw).Trim() -ne 'return 2') {
    throw 'Post-activation failure did not restore the old install.'
}
if (@(Get-ChildItem -LiteralPath (Join-Path $fixture 'archive') -Directory -Filter 'failed-install-*').Count -ne 1) {
    throw 'Failed installation was not preserved for diagnosis.'
}
& (Join-Path $fixtureTools 'package.ps1')
$zip = Join-Path $fixture 'dist/KryptonSurvivor-0.0.1.zip'
$originalHash = (Get-FileHash -LiteralPath $zip).Hash
Set-Content -LiteralPath (Join-Path $fixture 'mod/scripts/new.lua') -Value 'return 3'
& (Join-Path $fixtureTools 'package.ps1')
$oldZip = @(Get-ChildItem -LiteralPath (Join-Path $fixture 'archive/packages') -File)
if ($oldZip.Count -ne 1 -or (Get-FileHash -LiteralPath $oldZip[0].FullName).Hash -ne $originalHash) { throw 'Old package bytes were not preserved.' }
if ((Get-FileHash -LiteralPath $zip).Hash -eq $originalHash) { throw 'New package was not updated.' }
Write-Output 'Distribution tests passed: stale-file isolation, extra-file archival, rollback, retry, package history.'
