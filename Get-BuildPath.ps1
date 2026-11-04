$ErrorActionPreference='Stop'
# ModelSim 10.7 cannot open a library database below a Unicode path. A
# workspace-local junction gives native tools an ASCII spelling of this copy.
if($PSScriptRoot -notmatch '[^\x00-\x7F]'){ return $PSScriptRoot }
$workspace=Split-Path -Parent $PSScriptRoot
$alias=Join-Path $workspace '.tools\studio_project'
if(Test-Path -LiteralPath $alias){
    $item=Get-Item -LiteralPath $alias -Force
    if($item.LinkType -ne 'Junction' -or
       ![string]::Equals([string]$item.Target,$PSScriptRoot,[StringComparison]::OrdinalIgnoreCase)){
        throw "Build alias already points elsewhere: $alias"
    }
}else{
    New-Item -ItemType Junction -Path $alias -Target $PSScriptRoot | Out-Null
}
return $alias
