param([string]$JobPath, [switch]$Accounts, [switch]$WaitForExit)
$ErrorActionPreference = 'Stop'
try {
  $pythonPath = Join-Path $PSScriptRoot '.venv\Scripts\pythonw.exe'
  $bridgePath = Join-Path $PSScriptRoot 'hf_bridge.py'
  if (-not (Test-Path -LiteralPath $pythonPath)) { throw 'Run Setup.cmd in the HF Variations folder first.' }
  if ($Accounts) {
    $taskArgs = '"' + $bridgePath + '" --accounts'
  } else {
    if (-not (Test-Path -LiteralPath $JobPath)) { throw 'Job file not found.' }
    $taskArgs = '"' + $bridgePath + '" --job "' + $JobPath + '"'
  }
  $processOptions = @{FilePath=$pythonPath;ArgumentList=$taskArgs;WindowStyle='Hidden'}
  if ($WaitForExit) { $processOptions.Wait = $true }
  Start-Process @processOptions | Out-Null
} catch {
  if ($JobPath) {
    $statusPath = Join-Path (Split-Path -LiteralPath $JobPath) 'status.json'
    @{state='error';message=$_.Exception.Message;files=@()} | ConvertTo-Json | Set-Content -LiteralPath $statusPath -Encoding UTF8
  } else { throw }
  exit 1
}
