# update.ps1 - rebuild neon.css from your current MAL list and publish it (commit + push + CDN refresh).
# Run after you changed your list:   powershell -ExecutionPolicy Bypass -File update.ps1
# (The GitHub Action in .github/workflows does the same every day on its own.)
param([string]$Message = "Update neon.css")

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

& (Join-Path $PSScriptRoot "build.ps1")

git add neon.css
if (-not (git status --porcelain neon.css)) { Write-Host "neon.css did not change, nothing to publish."; return }
git commit -m $Message
git push

# jsDelivr caches branch files for hours; ask it to refresh
$remote = git remote get-url origin
if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)") {
  $purge = "https://purge.jsdelivr.net/gh/$($Matches[1])/$($Matches[2])@main/neon.css"
  try { Invoke-WebRequest -UseBasicParsing $purge | Out-Null; Write-Host "CDN refresh requested." } catch { Write-Warning "CDN refresh failed: $($_.Exception.Message)" }
}
