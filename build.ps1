param([string]$GowinTool='D:\Gowin\Gowin_V1.9.12.04_x64\IDE\bin\gw_sh.exe')
$ErrorActionPreference='Stop'
if(!(Test-Path -LiteralPath $GowinTool)){throw "Gowin compiler not found: $GowinTool"}
& (Join-Path $PSScriptRoot 'Restore-GowinConfig.ps1')
if($PSScriptRoot -match '[^\x00-\x7F]'){throw 'Move the project to an ASCII-only path for command-line compilation.'}
Push-Location -LiteralPath $PSScriptRoot
try { & $GowinTool 'build.tcl'; if($LASTEXITCODE -ne 0){throw "Gowin build failed: $LASTEXITCODE"} }
finally { Pop-Location }
Write-Output 'New build outputs are in impl/pnr. Published D2F1 files in programming are NOT overwritten automatically.'
