[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptsPath
)
$ErrorActionPreference = 'Stop'
$target = [IO.Path]::GetFullPath($ScriptsPath)
$source = Join-Path $PSScriptRoot 'huggingface-variations'
$destination = Join-Path $target 'huggingface-variations'
# Explicit source list: never deploy credentials, preferences, jobs, or a venv.
$files = @('Accounts.cmd', 'Login.cmd', 'Setup.cmd', 'launch.ps1',
    'requirements.txt', 'HF Animation.lua', 'HF Variations.lua', 'hf_bridge.py', 'README.md')
$launchers = @('HF Animation Launcher.lua', 'HF Variations Launcher.lua')
foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath (Join-Path $source $file) -PathType Leaf)) {
        throw "Missing source file: $file"
    }
}
if ($target.TrimEnd('\', '/') -ieq $PSScriptRoot.TrimEnd('\', '/')) {
    Write-Output 'This checkout is already installed in the selected Scripts folder.'
    return
}
if ($PSCmdlet.ShouldProcess($target, 'Install or update HF tool and launchers')) {
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    foreach ($file in $files) {
        Copy-Item -LiteralPath (Join-Path $source $file) -Destination (Join-Path $destination $file) -Force
    }
    foreach ($file in $launchers) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination (Join-Path $target $file) -Force
    }
    Write-Output "Installed to $destination. On first install, run Setup.cmd there, then rescan Aseprite scripts."
}
