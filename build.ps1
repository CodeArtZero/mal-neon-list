# build.ps1 - builds neon.css = src/base.css + parts generated from your live MAL list:
#   * high-res cover URLs for every anime (MAL "l.webp" = 424x600 instead of the 192x272 list thumbnail)
#   * hero graphic (score distribution + mean score)
#   * Episodes/Days stat cards
# neon.css is hosted on GitHub Pages; MAL only contains a one-line @import of it.
# With -GitHubUser and -Repo it also writes the stub PASTE-INTO-MAL.css (needed only once).
#
#   powershell -ExecutionPolicy Bypass -File build.ps1 [-GitHubUser name -Repo repo]
param([string]$User = "SynthesizedSoul", [string]$GitHubUser = "", [string]$Repo = "")

$ErrorActionPreference = "Stop"
$inv = [Globalization.CultureInfo]::InvariantCulture
$ua  = @{ "User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36" }

# ---------- 1. fetch the full list (MAL returns 300 entries per request) ----------
$all = @(); $offset = 0
do {
  $url   = "https://myanimelist.net/animelist/$User/load.json?offset=$offset&status=7"
  $chunk = (Invoke-WebRequest -UseBasicParsing -Headers $ua $url).Content | ConvertFrom-Json   # no @() here: PS 5.1 would wrap the array
  $all  += $chunk
  $offset += 300
} while ($chunk.Count -ge 300)
Write-Host "Loaded $($all.Count) entries"

# ---------- 2. numbers ----------
$scored   = @($all | Where-Object { $_.score -gt 0 })
$mean     = if ($scored.Count) { ($scored | Measure-Object score -Average).Average } else { 0 }
$dist     = 1..10 | ForEach-Object { $s = $_; @($scored | Where-Object { $_.score -eq $s }).Count }
$maxDist  = [Math]::Max(1, ($dist | Measure-Object -Maximum).Maximum)
function Count-Status($n) { @($all | Where-Object { $_.status -eq $n }).Count }
$cWatching  = Count-Status 1
$cCompleted = Count-Status 2
$cPlan      = Count-Status 6
$cOnHold    = Count-Status 3
$tens       = $dist[9]
$meanTxt    = $mean.ToString("0.00", $inv)

# ---------- 3. SVG helpers ----------
function To-DataUri([string]$svg) {
  $svg = ($svg -replace "\s+", " ").Trim()
  $svg = $svg -replace "> <", "><"
  $svg = [regex]::Replace($svg, "='(\d+\.\d)\d+'", "='`$1'")   # trim long decimals in attributes to keep the CSS small
  $svg = $svg -replace "%", "%25" -replace "<", "%3C" -replace ">", "%3E" -replace "#", "%23" -replace '"', "'"
  return "url(`"data:image/svg+xml,$svg`")"
}
$font = ""; $fam = "font-family='Segoe UI, Helvetica, Arial, sans-serif'"
$defs = @"
<defs>
<linearGradient id='edge' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#00e5ff'/><stop offset='.55' stop-color='#8b5cff'/><stop offset='1' stop-color='#ff2bd6'/></linearGradient>
<linearGradient id='txt' x1='0' y1='0' x2='1' y2='0'><stop offset='0' stop-color='#00e5ff'/><stop offset='1' stop-color='#ff2bd6'/></linearGradient>
<filter id='glow' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='3' result='b'/><feMerge><feMergeNode in='b'/><feMergeNode in='SourceGraphic'/></feMerge></filter>
</defs>
"@

$glowDef = "<defs><filter id='glow' x='-30%' y='-30%' width='160%' height='160%'><feGaussianBlur stdDeviation='3' result='b'/><feMerge><feMergeNode in='b'/><feMergeNode in='SourceGraphic'/></feMerge></filter></defs>"

# ---------- 4. hero graphic: score distribution + mean (440 x 156) ----------
$barColors = @("#7b82ad","#7b82ad","#7b82ad","#7b82ad","#7b82ad","#ffc531","#7aa2ff","#8b5cff","#00e5ff","#ff2bd6")
$bars = ""
for ($i = 0; $i -lt 10; $i++) {
  $h = [Math]::Round($dist[$i] / $maxDist * 66, 1)
  $x = 22 + $i * 25
  $y = 112 - $h
  if ($dist[$i] -gt 0) {
    $bars += "<rect x='$x' y='$($y.ToString($inv))' width='19' height='$($h.ToString($inv))' rx='3' fill='$($barColors[$i])' filter='url(#glow)'/>"
    $bars += "<text x='$($x + 9.5)' y='$(($y - 5).ToString($inv))' text-anchor='middle' font-size='9' fill='#8b8eb3' $font>$($dist[$i])</text>"
  }
  $bars += "<text x='$($x + 9.5)' y='128' text-anchor='middle' font-size='10' fill='#8b8eb3' $font>$($i + 1)</text>"
}
$heroSvg = @"
<svg xmlns='http://www.w3.org/2000/svg' width='440' height='156' viewBox='0 0 440 156' $fam>$defs
<rect x='.5' y='.5' width='439' height='155' rx='16' fill='#0f0f1d' fill-opacity='.78' stroke='url(#edge)' stroke-opacity='.8'/>
<text x='22' y='28' font-size='10' letter-spacing='3' fill='#8b8eb3' $font>SCORE DISTRIBUTION</text>
$bars
<line x1='284' y1='22' x2='284' y2='134' stroke='#ffffff' stroke-opacity='.1'/>
<text x='300' y='82' font-size='44' font-weight='700' fill='url(#txt)' filter='url(#glow)' $font>$meanTxt</text>
<text x='302' y='102' font-size='10' letter-spacing='2.5' fill='#8b8eb3' $font>MEAN SCORE</text>
<text x='302' y='122' font-size='10' letter-spacing='1.5' fill='#8b8eb3' $font>$($scored.Count) RATED / $($all.Count)</text>
</svg>
"@

# ---------- 5. stat cards (Completed tab only) ----------
# MAL renders "Eps" and "Days" in its page HTML; read them from the Completed tab
$html = (Invoke-WebRequest -UseBasicParsing -Headers $ua "https://myanimelist.net/animelist/$User`?status=2").Content
if ($html -notmatch "Eps:\s*(\d+),\s*Days:\s*([\d.]*)") { throw "Could not read Eps/Days from the Completed tab" }
$cEps  = ([int]$Matches[1]).ToString("N0", $inv)
$cDays = $Matches[2]

function Build-Cards($items, [int]$W, [int]$cols, [int]$gap, [int]$cardH, [int]$numSize) {
  $rows = [Math]::Ceiling($items.Count / $cols)
  $cw   = ($W - ($cols - 1) * $gap) / $cols
  $out  = ""
  for ($i = 0; $i -lt $items.Count; $i++) {
    $cx = ($i % $cols) * ($cw + $gap)
    $cy = [Math]::Floor($i / $cols) * ($cardH + $gap)
    $c  = $items[$i].c
    $out += "<rect x='$($cx.ToString($inv))' y='$($cy.ToString($inv))' width='$($cw.ToString($inv))' height='$cardH' rx='14' fill='#0f0f1d' fill-opacity='.85' stroke='$c' stroke-opacity='.5'/>"
    $out += "<rect x='$(($cx + 14).ToString($inv))' y='$(($cy + $cardH - 3).ToString($inv))' width='$(($cw - 28).ToString($inv))' height='2' rx='1' fill='$c' filter='url(#glow)'/>"
    $out += "<text x='$(($cx + 18).ToString($inv))' y='$(($cy + $cardH * 0.58).ToString($inv))' font-size='$numSize' font-weight='700' fill='$c' filter='url(#glow)' $font>$($items[$i].n)</text>"
    $out += "<text x='$(($cx + 19).ToString($inv))' y='$(($cy + $cardH * 0.82).ToString($inv))' font-size='10' letter-spacing='2' fill='#8b8eb3' $font>$($items[$i].l)</text>"
  }
  $height = $rows * $cardH + ($rows - 1) * $gap
  return "<svg xmlns='http://www.w3.org/2000/svg' width='$W' height='$height' viewBox='0 0 $W $height' $fam>$glowDef$out</svg>"
}
$statsSvg = Build-Cards @(
  @{ n = $cEps;  l = "EPISODES"; c = "#ffc531" },
  @{ n = $cDays; l = "DAYS";     c = "#ff2bd6" }
) 454 2 14 84 30


# ---------- 6. cover rules ----------
$covers = New-Object System.Text.StringBuilder
foreach ($a in $all) {
  if ($a.anime_image_path -match "/images/(anime/\d+/\d+)\.\w+") {
    [void]$covers.Append("[href^=`"/anime/$($a.anime_id)/`"]{--i:url(https://cdn.myanimelist.net/images/$($Matches[1])l.webp)}`n")
  }
}

# ---------- 7. write neon-cube.css ----------
$base = Get-Content -Raw -Encoding UTF8 (Join-Path (Join-Path $PSScriptRoot "src") "base.css")
$gen = @"

/* ==========================================================================
   Generated part: covers, hero graphic and stat cards, built from the live MAL list.
   ========================================================================== */

/* high-res covers: $($all.Count) entries (placed first so they survive if MAL ever cuts the CSS short) */
$($covers.ToString())
/* hero graphic, top right (hidden when the screen is too narrow for it) */
.list-container::before {
  content: "";
  position: absolute;
  top: 14px;
  right: 24px;
  width: 440px;
  height: 156px;
  background: $(To-DataUri $heroSvg) no-repeat center / contain;
  pointer-events: none;
}
@media (max-width: 1180px) { .list-container::before { display: none; } }

/* Completed tab: the MAL text strip becomes two cards, Episodes and Days (numbers read from MAL at build time) */
.list-unit.completed .list-stats {
  font-size: 0;
  line-height: 0;
  color: transparent;
  height: auto;
  width: min(454px, 100%);
  padding: 0;
  margin-bottom: 42px;
  position: relative;
  aspect-ratio: 454 / 84;
  background: $(To-DataUri $statsSvg) no-repeat center / 100% 100%;
  border: 0;
  border-radius: 0;
  box-shadow: none;
}
.list-unit.completed .list-stats::before,
.list-unit.completed .list-stats .score-label { display: none; }
.list-unit.completed .list-stats a.floatRightHeader {
  position: absolute;
  left: 4px;
  bottom: -26px;
  font-size: 12px;
  line-height: 1;
}
"@

$utf8 = New-Object System.Text.UTF8Encoding $false     # no BOM
$outFile = Join-Path $PSScriptRoot "neon.css"
[IO.File]::WriteAllText($outFile, ($base + $gen), $utf8)
$size = (Get-Item $outFile).Length
Write-Host ("Wrote {0} ({1:N0} bytes)" -f $outFile, $size)

# the small stub that goes into MAL: MAL strips url() from pasted CSS but leaves an @import of an external file alone
if ($GitHubUser -and $Repo) {
  $importUrl = "https://$($GitHubUser.ToLower()).github.io/$Repo/neon.css"
  $stub = "/* Neon Cube - the whole design is loaded from the file below */`n@\import `"$importUrl`";`n"
  [IO.File]::WriteAllText((Join-Path $PSScriptRoot "PASTE-INTO-MAL.css"), $stub, $utf8)
  Write-Host "Wrote PASTE-INTO-MAL.css (import stub for $importUrl)"
}
Write-Host ("Mean {0}, rated {1}, completed {2}, on hold {3}, 10/10: {4}" -f $meanTxt, $scored.Count, $cCompleted, $cOnHold, $tens)
