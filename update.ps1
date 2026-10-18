# update.ps1 - rebuild neon.css from your current MAL list and publish it (commit + push).
# GitHub Pages picks the new file up within a minute or two; browsers refresh it after about 10 minutes.
# Run after you changed your list:   powershell -ExecutionPolicy Bypass -File update.ps1
# (The GitHub Action in .github/workflows does the same every day on its own.)
param([string]$Message = "Update neon.css")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot
git pull --rebase --autostash

& (Join-Path $PSScriptRoot "build.ps1")

git add -A neon.css images
if (-not (git status --porcelain neon.css images)) { Write-Host "neon.css did not change, nothing to publish."; return }
git commit -m $Message
git push
