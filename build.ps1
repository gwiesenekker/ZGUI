# SCU-style Windows build entry point; the existing candidate publisher is shared.
[CmdletBinding()]
param([Parameter(Position=0)][string]$Lazbuild = $env:LAZBUILD)
$ErrorActionPreference = 'Stop'

function Find-Tool($Name, $Override, $Candidates) {
    if ($Override) {
        return (Get-Command -Name $Override -CommandType Application -ErrorAction Stop).Source
    }
    $onPath = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    foreach ($pattern in $Candidates) {
        $found = Get-Item -Path $pattern -ErrorAction SilentlyContinue |
            Where-Object { !$_.PSIsContainer } | Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw "Cannot find $Name. Install Lazarus or pass its lazbuild.exe path."
}

Push-Location -LiteralPath $PSScriptRoot
try {
    $roots = @('C:\lazarus') + @(foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if ($base) { Join-Path $base 'Lazarus' }
    })
    $tool = Find-Tool 'lazbuild.exe' $Lazbuild ($roots | ForEach-Object { "$_\lazbuild.exe" })
    # Keep all existing build/backup/recovery rules in one implementation.
    & "$PSScriptRoot/tools/build_zgui.cmd" $tool
    $result = $LASTEXITCODE
} catch {
    Write-Error $_ -ErrorAction Continue
    $result = 1
} finally {
    Pop-Location
}
exit $result
