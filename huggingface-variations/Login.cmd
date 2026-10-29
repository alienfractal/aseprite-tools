@echo off
cd /d "%~dp0"
if not exist ".venv\Scripts\hf.exe" (
  echo Run Setup.cmd first.
  pause
  exit /b 1
)
".venv\Scripts\hf.exe" auth login
pause
