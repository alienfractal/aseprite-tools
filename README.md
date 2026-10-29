# Aseprite tools

This repository is the source for the Lua scripts and the shared Hugging Face
Variations / Animation tool. The HF tool lives in `huggingface-variations/`.
Both launchers use that folder relative to their own location.

## Install directly

Clone or copy this repository into Aseprite's Scripts folder. Run
`huggingface-variations/Setup.cmd` to create the Python environment and set up
an account, then choose **File → Scripts → Rescan Scripts Folder**.
Run **HF Variations Launcher** or **HF Animation Launcher**.

## Deploy the HF tool to another Scripts folder

From PowerShell in this repository:

```powershell
.\Deploy-HF.ps1 -ScriptsPath 'D:\Aseprite\scripts' -WhatIf
.\Deploy-HF.ps1 -ScriptsPath 'D:\Aseprite\scripts'
```

Run `Setup.cmd` inside the deployed `huggingface-variations` folder on first
install. Python 3.10+ and Windows are required. Set up accounts on each computer;
encrypted accounts are tied to the Windows user and computer.

Deployment updates source files and launchers without deleting anything or copying
accounts, settings, generated jobs, or Python environments. Existing destination
preferences and accounts are preserved. Rerun Setup.cmd when requirements change.

## Sync changes

Edit the central checkout, commit and push changes here, then pull on other
computers. If using a separate deployment, rerun Deploy-HF.ps1 after pulling.
Changes made inside a deployed copy must be brought back to this checkout before
redeploying. Git sync is manual.

Local `*.local.json` files, `.venv/`, and `jobs/` are ignored by Git. The former
game-project copy is left intact; these launchers now use this repository's copy.
Existing job history remains in the former folder.

See [the HF guide](huggingface-variations/README.md) for usage and offline tests.
