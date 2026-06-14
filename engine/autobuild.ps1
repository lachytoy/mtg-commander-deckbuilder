<#
  RETIRED (session 4): superseded by engine/handbuild.ps1, which hand-authors the two Bracket-3
  builds (owned + optimal) for Tayam. Kept only as a generic algorithmic fallback for brand-new
  commanders. The current deck model is TWO Bracket-3 decks (keys `owned`/`optimal`), not 10.

  Auto-generate Owned + Recommended builds for brackets 1-5 from the enriched candidate pool.
  Reads data/deck-data.json (pool + commander) and any existing deck.json/variants.json (as the
  "known-good staples" set), writes data/variants.json with up to 10 builds (<bracket>-owned,
  <bracket>-recommended) + per-bracket meta (theme/wincons/howToPlay). Then run the engine
  -Stage build to enrich + Spellbook + validate, and -Stage inject to ship the HTML.

  Card SELECTION here is algorithmic (EDHREC inclusion + synergy + staples, bracket rules, chase
  exclusion, role template, manabase). Hand-polish the target bracket afterwards in variants.json.
#>
param([string]$Root, [int[]]$Brackets=@(1,2,3,4,5))
$ErrorActionPreference='Stop'
if(-not $Root){ $Root = Split-Path -Parent $PSScriptRoot }
$data = Join-Path $Root 'data'
$dd = Get-Content (Join-Path $data 'deck-data.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$commander = $dd.commander.name
$cmdCI = @($dd.commander.color_identity)
$pool = $dd.pool

# staples = every card I've already hand-authored into a build (known-good even if low EDHREC inclusion)
$staples=@{}
foreach($f in @('deck.json','variants.json')){
  $p=Join-Path $data $f
  if(Test-Path $p){ $j=Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json
    if($j.cards){ foreach($c in $j.cards){ $staples[$c.name.ToLower()]=$true } }
    if($j.variants){ foreach($vk in $j.variants.PSObject.Properties.Name){ foreach($c in $j.variants.$vk.cards){ $staples[$c.name.ToLower()]=$true } } } }
}

# "silly" cEDH chase cards excluded from RECOMMENDED buys (owned copies still allowed)
$chase=@{}
@('Savannah','Bayou','Scrubland','Tundra','Underground Sea','Taiga','Plateau','Volcanic Island','Tropical Island','Badlands',
  "Gaea's Cradle","Serra's Sanctum",'Ancient Tomb','Mana Vault','Grim Monolith','Chrome Mox','Mox Diamond','Mox Opal','Mox Emerald','Mox Jet','Mox Pearl','Mox Ruby','Mox Sapphire',
  "Lion's Eye Diamond",'Imperial Seal',"Mishra's Workshop",'The Tabernacle at Pendrell Vale','The One Ring','Cyclonic Rift','Mana Crypt','Jeweled Lotus') | ForEach-Object { $chase[$_.ToLower()]=$true }
# combo enablers pulled for casual brackets 1-2 (no intentional infinite combos)
$comboPieces=@{}
@("Ashnod's Altar",'Viscera Seer','Carrion Feeder',"Bartolome del Presidio","Bartolomé del Presidio",'Altar of Dementia','Phyrexian Altar','Devoted Druid','Vizier of Remedies','Walking Ballista','Basking Broodscale','Nim Deathmantle') | ForEach-Object { $comboPieces[$_.ToLower()]=$true }

$GCCAP=@{1=0;2=0;3=3;4=999;5=999}
# role templates: lands, ramp, draw, removal, wipes, protection (rest -> synergy to total 99)
$TPL=@{
  1=@{lands=38;ramp=10;draw=8;removal=5;wipe=1;prot=2}
  2=@{lands=37;ramp=10;draw=9;removal=6;wipe=2;prot=2}
  3=@{lands=36;ramp=10;draw=10;removal=7;wipe=3;prot=3}
  4=@{lands=35;ramp=11;draw=11;removal=8;wipe=3;prot=4}
  5=@{lands=33;ramp=12;draw=11;removal=8;wipe=2;prot=5}
}
# Tayam-specific play metadata per bracket (authored)
$META=@{
  1=@{theme='Ultra-casual counters & value — slow, durdly, battlecruiser';
      keep='Keep 2-4 lands with a mana dork or rock and at least one payoff (Cathars'' Crusade, Rishkar, or a counter-maker). Mulligan no-land or all-lands hands.';
      early='T1-3: ramp and drop cheap counter-creatures. No need to rush; you win late.';
      mid='T4-6: land Tayam, start recurring small permanents; build a wide counter board.';
      late='Grind value, out-resource the table, swing with counter-pumped creatures.';
      style='Politics-friendly, reactive. No combos — just a fair midrange board.'}
  2=@{theme='Precon-level counters/aristocrats — fair value, no combos';
      keep='2-4 lands + a dork/rock + a payoff or removal. Prioritise a turn-1 mana creature.';
      early='Ramp into Tayam; trade removal for early threats.';
      mid='Use Tayam to recur value creatures (Eternal Witness, removal-on-a-body); grow the board.';
      late='Win through combat + incremental aristocrat drain; Grave Pact locks opponents out.';
      style='Steady midrange. No infinite loops; rely on card quality + Tayam grind.'}
  3=@{theme='Upgraded counters / aristocrats / recursion with a late-game Tayam loop';
      keep='Aim for 3 lands + ramp + a payoff or a combo piece. Great keeps have Cathars'' Crusade or a sac outlet plus a dork.';
      early='T1-2 mana dork, T3 ramp/draw; deploy counter engines (Rishkar, Good-Fortune Unicorn).';
      mid='Land Tayam + a sac outlet; assemble Cathars'' Crusade + free sac outlet for the loop, or grind value.';
      late='Go off: loop sac+Cathars'' for infinite death triggers, drain with Blood Artist/Zulaport/Bastion, or Walking Ballista.';
      style='Flexible — combo when safe, otherwise grind. Hold protection (Heroic Intervention) for the combo turn.'}
  4=@{theme='High-power: faster, redundant combos, more interaction (no chase mana)';
      keep='Mulligan aggressively for ramp + a combo piece or tutor. 2-3 lands + acceleration is ideal.';
      early='Fast ramp; deploy a sac outlet or counter engine early.';
      mid='Tutor for and assemble the loop by turn 4-6; protect with interaction.';
      late='Close fast via the infinite-death-trigger drain or Walking Ballista; tutors give consistency.';
      style='Proactive combo-midrange. Sequence around protecting the combo turn; interact with rivals'' lines.'}
  5=@{theme='cEDH-leaning (budget — excludes the chase fast-mana/duals you skip)';
      keep='Keep only hands that can ramp hard or assemble/tutor toward the combo. Mulligan slow hands.';
      early='Maximise mana; deploy dorks; hold free/cheap interaction for opposing combos.';
      mid='Tutor + protect; go for the Tayam/Cathars'' loop as early as the (budget) mana allows.';
      late='Win on the combo turn with drain/Ballista; this build is intentionally missing the chase mana, so it is slower than true cEDH.';
      style='Tempo + interaction + combo. Note: without the excluded staples this is "budget cEDH", not tournament-tuned.'}
}

function Pip($mc,$col){ if(-not $mc){return 0}; ([regex]::Matches($mc,'\{'+$col+'\}')).Count }
function Score($c){ $s=0.0; if($c.inclusion_pct){$s+=[double]$c.inclusion_pct}; if($c.synergy){$s+=30.0*[double]$c.synergy}; if($staples.ContainsKey($c.name.ToLower())){$s+=18}; return $s }
function Eligible($c,$bracket,$mode){
  if(-not ($c.inclusion_pct -or $staples.ContainsKey($c.name.ToLower()))){ return $false }   # must be Tayam-relevant
  if($mode -eq 'owned' -and -not $c.owned){ return $false }
  if($mode -eq 'recommended' -and -not $c.owned -and $chase.ContainsKey($c.name.ToLower())){ return $false }
  if($bracket -le 2 -and $c.is_gc){ return $false }
  if($bracket -le 2 -and $comboPieces.ContainsKey($c.name.ToLower())){ return $false }
  return $true
}
function RoleBucket($r){ if($r -eq 'land'){'land'}elseif($r -eq 'ramp'){'ramp'}elseif($r -eq 'card-draw'){'draw'}elseif($r -eq 'spot-removal'){'removal'}elseif($r -eq 'board-wipe'){'wipe'}elseif($r -eq 'protection'){'prot'}else{'synergy'} }

function Build-One($bracket,$mode){
  $t=$TPL[$bracket]; $cap=$GCCAP[$bracket]
  $elig=@($pool | Where-Object { Eligible $_ $bracket $mode } | ForEach-Object { $_ | Add-Member -NotePropertyName _score -NotePropertyValue (Score $_) -Force -PassThru })
  $byRole=@{}; foreach($c in $elig){ $b=RoleBucket $c.role; if(-not $byRole.ContainsKey($b)){$byRole[$b]=New-Object System.Collections.ArrayList}; [void]$byRole[$b].Add($c) }
  foreach($k in @($byRole.Keys)){ $byRole[$k]=@($byRole[$k] | Sort-Object _score -Descending) }
  $picked=New-Object System.Collections.ArrayList; $usedNames=@{}; $state=@{gc=0}
  function TryAdd($c){ if($usedNames.ContainsKey($c.name.ToLower())){return $false}; if($c.is_gc -and $cap -lt 999 -and $state.gc -ge $cap){return $false}; [void]$picked.Add($c); $usedNames[$c.name.ToLower()]=$true; if($c.is_gc){$state.gc++}; return $true }
  # explicit nonland roles
  foreach($r in @('ramp','draw','removal','wipe','prot')){
    $need=$t[$r]; $i=0; $src=@(); if($byRole.ContainsKey($r)){$src=$byRole[$r]}
    foreach($c in $src){ if($need -le 0){break}; if(TryAdd $c){$need--} }
  }
  # synergy / flex = remaining nonland slots
  $landTarget=$t.lands; $nonlandTarget=99-$landTarget
  $flexNeed=$nonlandTarget-$picked.Count
  $flexSrc=@($elig | Where-Object { (RoleBucket $_.role) -ne 'land' } | Sort-Object _score -Descending)
  foreach($c in $flexSrc){ if($flexNeed -le 0){break}; if(TryAdd $c){$flexNeed--} }
  # if still short (thin pool), allow any remaining nonland
  # manabase: nonbasic lands (owned-first by score), then basics by pip weight
  $landSrc=@(); if($byRole.ContainsKey('land')){$landSrc=$byRole['land'] | Where-Object { $_.type_line -notmatch 'Basic Land' }}
  $reserveBasics=[Math]::Max(6,[int]($landTarget*0.32))
  $nbCount=[Math]::Min($landSrc.Count, $landTarget-$reserveBasics)
  $nbLands=@($landSrc | Select-Object -First $nbCount)
  foreach($c in $nbLands){ [void]$picked.Add($c); $usedNames[$c.name.ToLower()]=$true }
  $basicsNeed=$landTarget-$nbLands.Count
  $pip=@{W=0;U=0;B=0;R=0;G=0}
  foreach($c in $picked){ foreach($col in @('W','U','B','R','G')){ $pip[$col]+=(Pip $c.mana_cost $col) } }
  $cols=@($cmdCI); if($cols.Count -eq 0){$cols=@('C')}
  $bw=@{W='Plains';U='Island';B='Swamp';R='Mountain';G='Forest'}
  $tot=0; foreach($col in $cols){ $tot+=[Math]::Max(1,$pip[$col]) }
  $basics=@()
  $assigned=0
  for($k=0;$k -lt $cols.Count;$k++){ $col=$cols[$k]
    $n=[Math]::Floor($basicsNeed*([Math]::Max(1,$pip[$col])/$tot))
    if($k -eq $cols.Count-1){ $n=$basicsNeed-$assigned }
    $assigned+=$n
    if($n -gt 0){ $basics+=[pscustomobject]@{name=$bw[$col];role='land';count=[int]$n} }
  }
  # assemble card list (names + role + count)
  $cards=New-Object System.Collections.ArrayList
  foreach($c in $picked){ [void]$cards.Add([pscustomobject]@{name=$c.name;role=$c.role;count=1}) }
  foreach($b in $basics){ [void]$cards.Add($b) }
  $total=($cards | ForEach-Object { if($_.count){$_.count}else{1} } | Measure-Object -Sum).Sum
  return [pscustomobject]@{ cards=@($cards); total=$total; gc=$state.gc }
}

$variants=[ordered]@{}
foreach($b in $Brackets){
  foreach($mode in @('owned','recommended')){
    $r=Build-One $b $mode
    $m=$META[$b]
    $label=$(if($mode -eq 'owned'){'Fully owned'}else{'Recommended'})
    $theme=$(if($mode -eq 'owned'){'100% from your collection - '+$m.theme}else{$m.theme})
    $variants["$b-$mode"]=[pscustomobject]@{
      label=$label; bracket=$b; buildType=$mode; theme=$theme;
      wincons=@(); comboNotes=@();
      howToPlay=[pscustomobject]@{keep=$m.keep;early=$m.early;mid=$m.mid;late=$m.late;style=$m.style};
      cards=$r.cards; optionalBuys=@()
    }
    "[$b-$mode] cards=$($r.total) gc=$($r.gc)"
  }
}
$out=[pscustomobject]@{ commander=$commander; defaultVariant='3-recommended'; variants=$variants }
$out | ConvertTo-Json -Depth 10 | Out-File -Encoding utf8 (Join-Path $data 'variants.json')
"Wrote variants.json with $($variants.Count) builds."
