param([switch]$Force)
$ErrorActionPreference = 'Stop'
$name = 'guitar_penghuwan_ledguide_process_config.json'
$source = Join-Path $PSScriptRoot "config/$name"
$destination = Join-Path $PSScriptRoot "impl/$name"
if (!(Test-Path -LiteralPath $source)) { throw "Missing project configuration: $source" }
# Relocate an adopted incremental seed when this project folder is copied.
# Keep case-sensitive JSON keys intact (Gowin stores case-only duplicates).
$sourceText = Get-Content -LiteralPath $source -Raw
$incrementalPattern = '"INCREMENTAL_PLACE_AND_ROUTING"\s*:\s*"([^"]*)"'
$incremental = [regex]::Match($sourceText, $incrementalPattern)
if ($incremental.Success -and $incremental.Groups[1].Value -notin @('', '0', 'auto')) {
    $seed = Join-Path $PSScriptRoot 'config/incremental_reference_4DAB.pr'
    if (!(Test-Path -LiteralPath $seed)) { throw "Missing verified incremental seed: $seed" }
    $seedPath = [System.IO.Path]::GetFullPath($seed).Replace('\', '/')
    $replacement = '"INCREMENTAL_PLACE_AND_ROUTING": "' + $seedPath + '"'
    $relocated = [regex]::Replace($sourceText, $incrementalPattern, $replacement)
    if ($relocated -cne $sourceText) {
        [System.IO.File]::WriteAllText($source, $relocated, (New-Object System.Text.UTF8Encoding($false)))
        if (Test-Path -LiteralPath $destination) {
            $destinationText = Get-Content -LiteralPath $destination -Raw
            $destinationText = [regex]::Replace($destinationText, $incrementalPattern, $replacement)
            [System.IO.File]::WriteAllText($destination, $destinationText, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
}
if ($Force -or !(Test-Path -LiteralPath $destination)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}
# Gowin stores both Show_All_Warnings and show_all_warnings. Windows
# PowerShell's case-insensitive ConvertFrom-Json cannot read that format.
$config = Get-Content -LiteralPath $destination -Raw
if ($config -cnotmatch '"CPU"\s*:\s*true\s*[,}]') {
    throw 'CPU pins must be regular IO. Close Gowin, then run ./Restore-GowinConfig.ps1 -Force and reopen the project.'
}
foreach ($setting in @('Place_Option', 'Route_Option', 'Route_Maxfan', 'Replicate_Resources', 'Global_Freq', 'Run_Timing_Driven', 'INCREMENTAL_PLACE_AND_ROUTING')) {
    $pattern = '"' + $setting + '"\s*:\s*("[^"]*"|true|false|[0-9.]+)\s*[,}]'
    $expected = [regex]::Match((Get-Content -LiteralPath $source -Raw), $pattern)
    $actual = [regex]::Match($config, $pattern)
    if (!$expected.Success -or !$actual.Success -or $expected.Groups[1].Value -cne $actual.Groups[1].Value) {
        throw "Gowin setting $setting differs from the verified configuration. Close Gowin, run ./Restore-GowinConfig.ps1 -Force, then reopen the project."
    }
}
