<#
  MTG Commander Deckbuilder engine. See ../ENGINE.md for the full runbook + methodology.
  Stages:
    collection    parse a Moxfield CSV (or re-classify from existing owned.json) -> data/owned-cards.json (SHARED)
    gamechangers  fetch the official Game Changers list -> data/game-changers.json (SHARED)
    fetch         -Commander : EDHREC candidate pool -> data/<slug>/build-sheet.json + candidates-cards.json
    digest        -Commander : compact role-bucketed candidates.md to author from (read THIS, not owned-cards.json)
    build         -Commander : enrich variants.json -> deck-data.json + pool-data.json + oracle.md (+ Spellbook combos, VALIDATE before write)
    inject        -Commander : deck/pool-data + template -> <Commander>.html, deck-<slug>.txt; updates decks.json + index.html
    home          : regenerate the front-door index.html from index-template.html + data/decks.json

  Examples:
    .\engine\mtg-engine.ps1 -Stage collection -CollectionCsv "C:\path\moxfield_haves.csv"
    .\engine\mtg-engine.ps1 -Stage gamechangers
    .\engine\mtg-engine.ps1 -Stage fetch  -Commander "Atraxa, Praetors' Voice"
    .\engine\mtg-engine.ps1 -Stage build  -Commander "Atraxa, Praetors' Voice"
    .\engine\mtg-engine.ps1 -Stage inject -Commander "Atraxa, Praetors' Voice"
#>
param(
  [Parameter(Mandatory=$true)][ValidateSet('collection','gamechangers','fetch','digest','build','inject','home')][string]$Stage,
  [string]$Commander,
  [string]$Slug,
  [string]$CollectionCsv,
  [string]$DataDir,
  [string]$Root
)
$ErrorActionPreference='Stop'
# WORKSPACE vs CODE separation (so this can ship as an installed/shared plugin):
#   - Engine code + HTML templates are ALWAYS read from $PSScriptRoot (the engine/ folder, wherever installed).
#   - The user's data/decks/index.html (the "workspace") resolve via: -Root param > $env:MTG_WORKSPACE > engine parent.
# A friend installs the plugin once (read-only) and points MTG_WORKSPACE at their own folder; their decks never
# land inside the install. With neither set, it falls back to the engine's parent = the original in-repo layout.
if(-not $Root){ if($env:MTG_WORKSPACE){ $Root=$env:MTG_WORKSPACE } else { $Root=Split-Path -Parent $PSScriptRoot } }
$SharedData = Join-Path $Root 'data'
$UA=@{ 'User-Agent'='MTGDeckbuilder/0.3'; 'Accept'='application/json' }
New-Item -ItemType Directory -Force $Root | Out-Null
New-Item -ItemType Directory -Force $SharedData | Out-Null

function Read-Json($p){ Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save-Json($obj,$p){ $obj | ConvertTo-Json -Depth 12 -Compress | Out-File -Encoding utf8 $p }

# Retry transient network failures (429 / 5xx / connection drops) with backoff; honor Retry-After.
# One flaky response no longer aborts a multi-batch stage.
function Invoke-Retry([scriptblock]$Action,[int]$Max=3){
  for($attempt=1;;$attempt++){
    try{ return (& $Action) }
    catch{
      $resp=$null; try{ $resp=$_.Exception.Response }catch{}
      $code=$null; if($resp){ try{ $code=[int]$resp.StatusCode }catch{} }
      $retryable = (-not $code) -or ($code -ge 500) -or ($code -eq 429)
      if($attempt -ge $Max -or -not $retryable){ throw }
      $wait=[math]::Min(8,[math]::Pow(2,$attempt))   # 2s, 4s, 8s
      if($resp){ try{ $ra=$resp.Headers['Retry-After']; if($ra){ $wait=[double]$ra } }catch{} }
      Write-Warning ("Request failed (attempt $attempt/$Max" + $(if($code){", HTTP $code"}else{", $($_.Exception.Message)"}) + "); retrying in $wait s...")
      Start-Sleep -Seconds $wait
    }
  }
}

# --- Game Changers (official Scryfall list): fetch helper + first-run auto-fetch so build never crashes on a missing file ---
function Get-GameChangersList(){
  $r=Invoke-Retry { Invoke-RestMethod -Uri 'https://api.scryfall.com/cards/search?q=is%3Agamechanger&order=name&unique=cards' -Headers $UA -TimeoutSec 60 }
  $gc=New-Object System.Collections.ArrayList
  $gc.AddRange(@($r.data | Select-Object -Expand name))
  while($r.has_more){ Start-Sleep -Milliseconds 120; $next=$r.next_page; $r=Invoke-Retry { Invoke-RestMethod -Uri $next -Headers $UA -TimeoutSec 60 }; $gc.AddRange(@($r.data | Select-Object -Expand name)) }
  ,@($gc | Sort-Object -Unique)
}
function Ensure-GameChangers(){
  $p=Join-Path $SharedData 'game-changers.json'
  if(Test-Path $p){ return }
  "game-changers.json missing - fetching the official list from Scryfall (first run)..."
  $gc=Get-GameChangersList; Save-Json @($gc) $p; "Game Changers: $($gc.Count)"
}

# --- home / library page: a decks.json manifest + a regenerated front-door index.html ---
function Upsert-Deck($entry){
  $mp=Join-Path $SharedData 'decks.json'
  $decks=New-Object System.Collections.ArrayList
  if(Test-Path $mp){ $cur=Read-Json $mp; foreach($d in @($cur)){ if($d.slug -ne $entry.slug){ [void]$decks.Add($d) } } }
  [void]$decks.Add([pscustomobject]$entry)
  # always serialize as a JSON ARRAY (PS5.1 ConvertTo-Json -Compress unwraps a 1-element array into a bare
  # object - which a friend's very first deck would hit); emit []/[{...}] explicitly for the 0/1 cases.
  $arr=@($decks | Sort-Object { $_.name })
  $json=if($arr.Count -eq 0){'[]'} elseif($arr.Count -eq 1){'['+($arr[0]|ConvertTo-Json -Depth 12 -Compress)+']'} else {$arr|ConvertTo-Json -Depth 12 -Compress}
  $json | Out-File -Encoding utf8 $mp
}
function HtmlEnc([string]$s){ if($null -eq $s){return ''}; return ($s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;') }
function SafeImg([string]$u){ if($u -and $u -match '^https://'){ return ((HtmlEnc $u) -replace "'",'%27') }; return '' }
$script:IDC=@{W='#e9d9a6';U='#73a9e6';B='#9d80cf';R='#e07a5a';G='#5cc46f';C='#9aa6bd'}
function IdGradient($identity){ $cs=@(@($identity) | ForEach-Object { if($script:IDC[$_]){$script:IDC[$_]}else{$script:IDC['C']} }); if(-not $cs.Count){$cs=@($script:IDC['C'])}; if($cs.Count -eq 1){$cs=@($cs[0],$cs[0])}; return 'linear-gradient(90deg,'+($cs -join ',')+')' }
function Get-ManaSprite(){ $p=Join-Path $PSScriptRoot 'mana-sprite.svg'; if(Test-Path $p){ return ((Get-Content $p -Raw -Encoding UTF8) -replace "^﻿","") }; return '' }
function Update-Home(){
  $tplPath=Join-Path $PSScriptRoot 'index-template.html'
  if(-not (Test-Path $tplPath)){ return }   # no front-door template -> skip silently
  $mp=Join-Path $SharedData 'decks.json'
  $decks=@(); if(Test-Path $mp){ $tmp=Read-Json $mp; $decks=@($tmp) }
  $LBL=@{owned='Fully owned';optimal='Optimal';synergy='Commander-centric'}
  $tiles=@($decks | ForEach-Object { $d=$_
    $pips=(@($d.identity) | ForEach-Object { "<svg class=`"pip`" role=`"img`" aria-label=`"$_`"><use href=`"#ms-$_`"/></svg>" }) -join ''
    $builds=(@($d.builds) | ForEach-Object { if($LBL[$_]){$LBL[$_]}else{$_} }) -join ' / '
    $buildChip=$(if($builds){"<span class=`"chip`">$(HtmlEnc $builds)</span>"}else{''})
    $counts="<span class=`"chip`"><b>$($d.ownedCount)</b> owned</span>"
    if($d.buyCount){ $counts+="<span class=`"chip`"><b>$($d.buyCount)</b> to buy</span>" }
    $art=(SafeImg ($d.image -replace '/normal/','/art_crop/'))
    $idgrad=(IdGradient $d.identity)
    $brk=$(if($d.bracket){"<span class=`"chip`">Bracket $($d.bracket)</span>"}else{''})
    $combo=$(if([int]$d.comboCount -gt 0){"<span class=`"chip combo`">&#8734; $($d.comboCount) combo$(if([int]$d.comboCount -ne 1){'s'})</span>"}else{''})
    $theme=$(if($d.theme){"<div class=`"th`">$(HtmlEnc $d.theme)</div>"}else{''})
    "<a class=`"deck`" href=`"$(HtmlEnc $d.file)`"><div class=`"art`" style=`"background-image:url('$art')`"><div class=`"nmover`">$(HtmlEnc $d.name)<span class=`"pips`">$pips</span></div><div class=`"idstrip`" style=`"background:$idgrad`"></div></div><div class=`"body`"><div class=`"toprow`">$buildChip$brk$combo</div>$theme<div class=`"meta`">$counts</div><div class=`"foot`"><span class=`"open`">Open deck &rarr;</span><span class=`"date`">$(HtmlEnc $d.builtAt)</span></div></div></a>"
  })
  $decksHtml="<h2 class=`"sec`">Your decks<span class=`"cnt`">$($decks.Count)</span></h2>"
  if($decks.Count){ $decksHtml+="<div class=`"grid`">"+($tiles -join '')+'</div>' }
  else {
    $emptyIc="<svg class=`"ic`" viewBox=`"0 0 32 32`" xmlns=`"http://www.w3.org/2000/svg`" aria-hidden=`"true`"><g transform=`"translate(16 16)`"><circle cx=`"0`" cy=`"-7`" r=`"4.4`" fill=`"#f5e7c6`"/><circle cx=`"6.7`" cy=`"-2.2`" r=`"4.4`" fill=`"#bcd9f0`"/><circle cx=`"4.1`" cy=`"5.7`" r=`"4.4`" fill=`"#c4b7d6`"/><circle cx=`"-4.1`" cy=`"5.7`" r=`"4.4`" fill=`"#f0b9a6`"/><circle cx=`"-6.7`" cy=`"-2.2`" r=`"4.4`" fill=`"#bfe3c4`"/></g></svg>"
    $decksHtml+="<div class=`"empty`">$emptyIc<h3>Build your first deck</h3><p>Use the prompt above with the <b>mtg-deckbuilder</b> skill and your finished deck lands here &mdash; with a fully-owned and an optimal build, buy upgrades, detected combos, and a how-to-play guide.</p></div>"
  }
  $count=0; $ocp=Join-Path $SharedData 'owned-cards.json'; if(Test-Path $ocp){ $oc=Read-Json $ocp; $count=@($oc).Count }
  $collHtml=$(if($count){"<b>$($count.ToString('N0'))</b> cards classified in your collection"}else{'No collection imported yet'})
  $tpl=Get-Content $tplPath -Raw -Encoding UTF8
  $tpl.Replace('__DECKS_HTML__',$decksHtml).Replace('__COLLECTION_HTML__',$collHtml).Replace('__MANA_SPRITE__',(Get-ManaSprite)) | Out-File -Encoding utf8 (Join-Path $Root 'index.html')
}
function Get-EdhrecSlug([string]$name){
  $s=$name.ToLowerInvariant()
  $s=($s.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','')
  $s=$s -replace '[^a-z0-9]+','-' -replace '(^-+|-+$)',''
  return $s
}
function Get-Role([string]$tl,[string]$ora){
  $t=$tl.ToLower(); $o=$ora.ToLower()
  if($t -match 'land'){return 'land'}
  # ramp: mana abilities / treasure / extra land drop, or a land-SEARCH that lands it onto the battlefield (a land tutor to hand is not ramp)
  if($o -match '\{t\}: add|add \{|create a treasure|play an additional land|search your library for .{0,50}(land|forest|plains|swamp|island|mountain).{0,60}(onto the battlefield|into play)'){return 'ramp'}
  if($o -match 'destroy all|exile all|deals \d+ damage to each creature|each creature gets -|each player sacrifices'){return 'board-wipe'}
  if($o -match '(destroy|exile) target|target creature gets -|counter target'){return 'spot-removal'}
  # card-draw: YOU draw, not opponents / symmetrical "each player draws"
  if(($o -match 'you draw|draw (a|one|two|three|x|that many|\w+) cards?') -and ($o -notmatch "opponent.{0,20}draws?|each player draws|target player draws|defending player draws")){return 'card-draw'}
  if($o -match 'return .*(from|in) your graveyard'){return 'recursion'}
  if($o -match 'hexproof|indestructible|protection from|phase out|prevent all'){return 'protection'}
  return 'synergy'
}
# Function tags = what a card actually DOES (multi-label, from oracle). Drives "replace by contribution".
function Get-Tags([string]$tl,[string]$ora){
  $t=("$tl").ToLower(); $o=("$ora").ToLower(); $g=@()
  if($t -match 'land'){ $g+='land' }
  if(($o -match 'you draw|draw (a|one|two|three|four|five|x|that many|\w+) cards?') -and ($o -notmatch "opponent.{0,20}draws?|each player draws|target player draws|defending player draws")){ $g+='draw' }
  if($o -match '\{t\}: add|add \{[wubrgc]|create a treasure|treasure token|play an additional land|search your library for .{0,50}(land|basic|forest|plains|swamp|island|mountain).{0,60}(onto the battlefield|into play)'){ $g+='ramp' }
  if($o -match 'destroy all|exile all|destroy each|deals \d+ damage to each creature|all creatures get -|each player sacrifices'){ $g+='wipe' }
  if($o -match '(destroy|exile) target|target creature gets -\d|deals \d+ damage to (target|any target)|fights? (target|another)'){ $g+='removal' }
  if($o -match 'counter target'){ $g+='counterspell' }
  if($o -match 'return .{0,40}(from your graveyard|from a graveyard|in your graveyard)'){ $g+='recursion' }
  if($o -match '\+1/\+1 counter|proliferate'){ $g+='counters' }
  if($o -match 'sacrifice (a|an|another|one|two|three|x) (creature|permanent|artifact|token)|: sacrifice|whenever .{0,45}dies|when .{0,28} dies,'){ $g+='sacrifice' }
  if($o -match 'create .{0,28}token'){ $g+='tokens' }
  if($o -match 'each opponent loses|loses \d+ life|target (player|opponent) loses|drains?'){ $g+='drain' }
  if($o -match 'gain \d+ life|you gain life|lifelink'){ $g+='lifegain' }
  if($o -match 'creatures you control get \+|other creatures you control get \+'){ $g+='anthem' }
  if($o -match 'hexproof|indestructible|protection from|\bward\b|phase out|prevent all|gains? shroud'){ $g+='protection' }
  if(($o -match "can't be blocked|\btrample\b|\bdouble strike\b|\bmenace\b|\bflying\b") -and ($o -notmatch "lose.{0,8}(flying|trample|menace)|can't have (flying|trample|menace)")){ $g+='evasion' }
  if($o -match "cost \{\d|spells? cost|can't cast|can't search|don't untap|each opponent can't|unless that player pays"){ $g+='stax' }
  if(($o -match 'search your library for a') -and ($g -notcontains 'ramp')){ $g+='tutor' }
  # --- capability tags: let the app map Commander Spellbook "requires" templates to addable cards ---
  if($o -match '\bpersist\b'){ $g+='persist' }                                  # template "Persist Creature"
  if(($t -match 'creature') -and ($o -match '\{t\}:\s*add')){ $g+='manadork' }   # template "Mana dork"
  # free (no-mana, no-tap) repeatable sac outlet: "Sacrifice a creature:" that BEGINS an activated ability
  # (excludes tap-gated lands like Phyrexian Tower "{T}, Sacrifice a creature:" and self-saccing token text)
  if($o -match '(^|\.\s|\n|"\s?|\)\s)sacrifice (a|an|another|one|two|x) (creature|permanent)s?\s*:'){ $g+='freesac' }
  if($o -match 'creatures you control (have|gain)[^.]{0,45}haste|(target|another target|each) creature[^.]{0,45}gains? haste|gain haste until end of turn'){ $g+='hastegiver' }   # template "Haste enabler"
  if($o -match 'untap (target|another target|each|all|up to \w+ target) (creature|permanent|artifact|nonland)'){ $g+='untapper' }                                                       # template "Untapper"
  if($o -match 'twice that many[^.]{0,30}token|create twice as many|one or more tokens would be created[^.]{0,50}twice'){ $g+='tokendoubler' }                                            # template "Token doubler"
  if($o -match 'twice that many[^.]{0,30}\+1/\+1 counter|twice that many[^.]{0,30}counters|double the number of \+1/\+1'){ $g+='counterdoubler' }                                       # template "Counter doubler"
  if($o -match 'exile[^.]{0,80}return (it|them|those cards|that card)[^.]{0,35}(to the battlefield|under (its|your) (owner|control))'){ $g+='flicker' }                                  # template "Blink/flicker outlet"
  if($g.Count -eq 0 -and $t -match 'creature'){ $g+='body' }
  if($g.Count -eq 0){ $g+='other' }
  ,@($g | Select-Object -Unique)
}
# Returns hashtable lower(name) -> enriched scryfall object. Batches <=70, UTF-8 body.
function Get-ScryfallCards([string[]]$names){
  $map=@{}
  $u=@($names | Where-Object {$_} | Select-Object -Unique)
  $notFound=New-Object System.Collections.ArrayList
  for($i=0;$i -lt $u.Count;$i+=70){
    $hi=[Math]::Min($i+69,$u.Count-1); $chunk=$u[$i..$hi]
    # DFC / split names ("Front // Back") 404 on Scryfall - send only the FRONT FACE as the identifier.
    $ids=@($chunk | ForEach-Object { @{ name=(("$_" -split ' // ')[0]).Trim() } })
    $body=@{ identifiers=$ids } | ConvertTo-Json -Depth 4
    $bytes=[Text.Encoding]::UTF8.GetBytes($body)
    $resp=Invoke-Retry { Invoke-RestMethod -Uri 'https://api.scryfall.com/cards/collection' -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -Headers $UA -TimeoutSec 60 }
    foreach($c in $resp.data){
      $img=$null;$imgS=$null
      if($c.image_uris){$img=$c.image_uris.normal;$imgS=$c.image_uris.small}
      elseif($c.card_faces -and $c.card_faces[0].image_uris){$img=$c.card_faces[0].image_uris.normal;$imgS=$c.card_faces[0].image_uris.small}
      $ora=$c.oracle_text; if(-not $ora -and $c.card_faces){$ora=($c.card_faces|ForEach-Object{$_.oracle_text}) -join ' // '}
      $price=$c.prices.usd; if(-not $price){$price=$c.prices.usd_foil}; if(-not $price){$price=$c.prices.usd_etched}
      $obj=[pscustomobject]@{name=$c.name;cmc=$c.cmc;type_line=$c.type_line;mana_cost=$c.mana_cost;oracle_text=$ora;color_identity=$c.color_identity;legal=$c.legalities.commander;price_usd=$price;image=$img;image_small=$imgS}
      $map[$c.name.ToLower()]=$obj
      # also key by the front face so a deck/lookup that names only "Front" still resolves
      $front=(($c.name -split ' // ')[0]).Trim().ToLower()
      if($front -and $front -ne $c.name.ToLower()){ $map[$front]=$obj }
    }
    if($resp.not_found){ foreach($nf in $resp.not_found){ if($nf.name){ [void]$notFound.Add($nf.name) } } }
    Start-Sleep -Milliseconds 110
  }
  if($notFound.Count){ Write-Warning "Scryfall could not classify $($notFound.Count) name(s): $((@($notFound)|Select-Object -First 8) -join ', ')$(if($notFound.Count -gt 8){' ...'})" }
  return $map
}
function Get-Combos([string]$cmd,$enrichedCards){
  $main=@($enrichedCards | ForEach-Object { @{ card=$_.name; quantity=$(if($_.count){$_.count}else{1}) } })
  $body=@{ commanders=@(@{card=$cmd}); main=$main } | ConvertTo-Json -Depth 5
  $bytes=[Text.Encoding]::UTF8.GetBytes($body)
  try{
    $r=Invoke-Retry { Invoke-RestMethod -Uri 'https://backend.commanderspellbook.com/find-my-combos' -Method Post -Body $bytes -ContentType 'application/json; charset=utf-8' -Headers $UA -TimeoutSec 60 }
    ,@($r.results.included | Sort-Object {-([int]$_.popularity)} | Select-Object -First 40 | ForEach-Object {
      $co=$_
      $cards=@($co.uses | ForEach-Object {
        $st=''; foreach($s in @($_.battlefieldCardState,$_.graveyardCardState,$_.handCardState,$_.exileCardState,$_.libraryCardState)){ if($s){ $st=[string]$s; break } }
        [pscustomobject]@{ name=$_.card.name; img=$_.card.imageUriFrontSmall; imgFull=$_.card.imageUriFrontNormal; zones=@($_.zoneLocations); state=$st }
      })
      $reqs=@($co.requires | ForEach-Object {
        $st=''; foreach($s in @($_.battlefieldCardState,$_.graveyardCardState,$_.handCardState,$_.exileCardState,$_.libraryCardState)){ if($s){ $st=[string]$s; break } }
        [pscustomobject]@{ name=$_.template.name; zones=@($_.zoneLocations); state=$st }
      })
      $steps=@(($co.description -split "`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
      $prq=@(@($co.notablePrerequisites,$co.easyPrerequisites) | Where-Object { $_ })
      [pscustomobject]@{
        id=$co.id; url=('https://commanderspellbook.com/combo/'+$co.id+'/');
        cards=$cards; requires=$reqs;
        produces=@($co.produces | ForEach-Object { $_.feature.name });
        steps=$steps; prereq=($prq -join ' '); mana=$co.manaNeeded; bracket=$co.bracketTag; popularity=[int]$co.popularity
      }
    })
  } catch { ,@() }
}
function Resolve-DataDir(){
  if($DataDir){ return $DataDir }
  if(-not $Slug){ if($Commander){ $script:Slug=Get-EdhrecSlug $Commander } }
  return (Join-Path $SharedData $Slug)
}

switch($Stage){

 'collection' {
   $ownedPath=Join-Path $SharedData 'owned.json'
   if($CollectionCsv){
     $csv=Import-Csv $CollectionCsv
     $grouped=$csv | Group-Object Name | ForEach-Object {
       $sum=($_.Group | ForEach-Object { [int]($_.Count) } | Measure-Object -Sum).Sum
       [pscustomobject]@{ name=$_.Name; count=$sum } }
     Save-Json $grouped $ownedPath
   } elseif(Test-Path $ownedPath){
     "No -CollectionCsv given - re-classifying from existing owned.json (e.g. after an engine change)."
     $tmpg=Read-Json $ownedPath; $grouped=@($tmpg)
   } else {
     throw 'collection stage needs -CollectionCsv (or an existing data/owned.json to re-classify)'
   }
   $names=@($grouped | ForEach-Object { $_.name } | Where-Object { $_ })
   "Owned unique names: $($names.Count) - classifying via Scryfall..."
   $map=Get-ScryfallCards $names
   # the map carries front-face alias keys for DFCs, so dedupe to one object per card name
   $classified=@($map.Values | Sort-Object name -Unique)
   Save-Json $classified (Join-Path $SharedData 'owned-cards.json')
   "Wrote owned.json + owned-cards.json (classified $($classified.Count) of $($names.Count) names)."
 }

 'gamechangers' {
   $gc=Get-GameChangersList
   Save-Json @($gc) (Join-Path $SharedData 'game-changers.json')
   "Game Changers: $($gc.Count)"
 }

 'fetch' {
   if(-not $Commander){ throw 'fetch stage needs -Commander' }
   if(-not $Slug){ $Slug=Get-EdhrecSlug $Commander }
   $dir=Resolve-DataDir; New-Item -ItemType Directory -Force $dir | Out-Null
   "Commander: $Commander | slug: $Slug"
   $edhUrl="https://json.edhrec.com/pages/commanders/$Slug.json"
   Invoke-Retry { Invoke-WebRequest -Uri $edhUrl -Headers $UA -OutFile (Join-Path $dir 'edhrec.json') -TimeoutSec 60 | Out-Null }
   $j=Read-Json (Join-Path $dir 'edhrec.json')
   $cl=$null
   if($j.container -and $j.container.json_dict -and $j.container.json_dict.cardlists){ $cl=$j.container.json_dict.cardlists }
   elseif($j.json_dict -and $j.json_dict.cardlists){ $cl=$j.json_dict.cardlists }
   if(-not $cl){ throw "EDHREC cardlists not found for slug '$Slug' - verify the URL resolves: $edhUrl" }
   $parsed=foreach($list in $cl){ foreach($c in $list.cardviews){ [pscustomobject]@{category=$list.header;name=$c.name;num_decks=$c.num_decks;potential_decks=$c.potential_decks;synergy=$c.synergy} } }
   # guard: a near-empty payload (cardlists present but tiny) would silently build against an empty pool
   if(@($parsed).Count -lt 50){ throw "EDHREC returned only $(@($parsed).Count) candidates for slug '$Slug' - the page is likely empty/stale. Verify $edhUrl" }
   $names=@($parsed | Select-Object -Expand name -Unique)
   if($names -notcontains $Commander){ $names+=$Commander }
   # reuse the already-classified collection; only hit Scryfall for names not already known
   $ownedMap=@{}; $ownedCardsPath=Join-Path $SharedData 'owned-cards.json'
   if(Test-Path $ownedCardsPath){ foreach($c in (Read-Json $ownedCardsPath)){ $ownedMap[$c.name.ToLower()]=$c; $ff=(($c.name -split ' // ')[0]).Trim().ToLower(); if(-not $ownedMap.ContainsKey($ff)){$ownedMap[$ff]=$c} } }
   $need=@($names | Where-Object { $_ -and -not $ownedMap.ContainsKey($_.ToLower()) } | Select-Object -Unique)
   "EDHREC categories: $($cl.Count) | unique candidates: $($names.Count) | reused from collection: $($names.Count - $need.Count) | fetching $($need.Count) from Scryfall..."
   $fetched=@{}; if($need.Count){ $fetched=Get-ScryfallCards $need }
   # candidate map scoped to the EDHREC names only (reused-owned + freshly-fetched), so candidates-cards.json stays small
   $scry=@{}; foreach($nm in $names){ $k=$nm.ToLower(); $sc=$ownedMap[$k]; if(-not $sc){ $sc=$fetched[$k] }; if($sc){ $scry[$k]=$sc } }
   $ownedPath=Join-Path $SharedData 'owned.json'
   $ownedSet=@{}; if(Test-Path $ownedPath){ foreach($o in (Read-Json $ownedPath)){ $n=$o.name.ToLower();$ownedSet[$n]=$true; if($n -match ' // '){$ownedSet[(($n -split ' // ')[0])]=$true} } }
   Ensure-GameChangers
   $gcPath=Join-Path $SharedData 'game-changers.json'
   $gcSet=@{}; if(Test-Path $gcPath){ foreach($g in (Read-Json $gcPath)){ $gcSet[$g.ToLower()]=$true } }
   $cmdSc=$scry[$Commander.ToLower()]; $cmdCI=@(); if($cmdSc){$cmdCI=@($cmdSc.color_identity)}
   $byName=$parsed | Group-Object name
   $sheet=foreach($g in $byName){
     $nm=$g.Name; $sc=$scry[$nm.ToLower()]
     $nd=($g.Group|ForEach-Object{[int]$_.num_decks}|Measure-Object -Maximum).Maximum
     $pd=($g.Group|ForEach-Object{[int]$_.potential_decks}|Measure-Object -Maximum).Maximum
     $syn=[double]($g.Group|Sort-Object {[double]$_.synergy} -Descending|Select-Object -First 1).synergy
     $incl=0; if($pd -gt 0){$incl=[math]::Round(100.0*$nd/$pd,1)}
     $ci=@(); if($sc){$ci=@($sc.color_identity)}
     $ciLegal=$true; foreach($col in $ci){ if($cmdCI -notcontains $col){$ciLegal=$false} }
     [pscustomobject]@{name=$nm;categories=@($g.Group|Select-Object -Expand category -Unique);inclusion_pct=$incl;synergy=$syn;owned=$ownedSet.ContainsKey($nm.ToLower());cmc=$(if($sc){[double]$sc.cmc}else{-1});type_line=$(if($sc){$sc.type_line}else{''});color_identity=($ci -join '');ci_legal=$ciLegal;legal=$(if($sc){$sc.legal}else{'unknown'});price_usd=$(if($sc -and $sc.price_usd){[double]$sc.price_usd}else{$null});is_gc=$gcSet.ContainsKey($nm.ToLower())}
   }
   Save-Json @($sheet) (Join-Path $dir 'build-sheet.json')
   Save-Json @($scry.Values | Sort-Object name -Unique) (Join-Path $dir 'candidates-cards.json')   # oracle/type cache for the digest stage (deduped: map has DFC alias keys)
   $cand=$sheet | Where-Object { $_.name -ne $Commander }
   "Candidates: $($cand.Count) | owned: $(@($cand|?{$_.owned}).Count) | GC in pool: $(@($cand|?{$_.is_gc}).Count)"
   "Owned candidates (build the deck from these first):"
   $cand | Where-Object {$_.owned} | Sort-Object inclusion_pct -Descending | Select-Object -First 60 | ForEach-Object { "  {0,5}%  {1}  | {2}" -f $_.inclusion_pct,$_.name,$_.type_line }
   "`nNext: run -Stage digest, hand-author $dir\variants.json (the owned + optimal builds), then -Stage build."
 }

 'digest' {
   # Compact, role-bucketed candidate shortlist for the AI deckbuilding step (read this, NOT the 1.7MB collection).
   if(-not $Commander){ throw 'digest stage needs -Commander' }
   if(-not $Slug){ $Slug=Get-EdhrecSlug $Commander }
   $dir=Resolve-DataDir
   if(-not (Test-Path (Join-Path $SharedData 'owned-cards.json'))){ throw "No collection imported yet. Run '-Stage collection -CollectionCsv <your moxfield_haves.csv>' first (see ENGINE.md)." }
   if(-not (Test-Path (Join-Path $dir 'build-sheet.json'))){ throw "No build-sheet.json in '$dir'. Run '-Stage fetch -Commander `"$Commander`"' first." }
   $bs=Read-Json (Join-Path $dir 'build-sheet.json')
   $ownedCards=Read-Json (Join-Path $SharedData 'owned-cards.json')
   $oracle=@{}; foreach($c in $ownedCards){ $oracle[$c.name.ToLower()]=$c }
   foreach($f in @('candidates-cards.json','scryfall-cards.json')){ $p=Join-Path $dir $f; if(-not (Test-Path $p)){ $p=Join-Path $SharedData $f }
     if(Test-Path $p){ foreach($c in (Read-Json $p)){ $k=$c.name.ToLower(); if(-not $oracle.ContainsKey($k)){ $oracle[$k]=$c } } } }
   $cmdCI=@(); $cl=$oracle[$Commander.ToLower()]
   if($cl){ $cmdCI=@($cl.color_identity) } else { $m=Get-ScryfallCards @($Commander); $mm=$m[$Commander.ToLower()]; if($mm){ $cmdCI=@($mm.color_identity); $oracle[$Commander.ToLower()]=$mm } }
   function RoleFor($name,$tl){ $sc=$oracle[$name.ToLower()]; $o=''; if($sc -and $sc.oracle_text){ $o=$sc.oracle_text }; Get-Role $tl $o }
   $ORD=@('ramp','card-draw','spot-removal','board-wipe','protection','recursion','tutor','land','synergy')
   $LBL=@{ramp='Ramp';'card-draw'='Card draw';'spot-removal'='Removal';'board-wipe'='Board wipes';protection='Protection';recursion='Recursion';tutor='Tutors';land='Lands';synergy='Synergy / other'}
   $sb=New-Object System.Text.StringBuilder
   [void]$sb.AppendLine("# Candidate digest - $Commander ($($cmdCI -join '/'))")
   $pool=@($bs | Where-Object { $_.ci_legal -and $_.legal -ne 'banned' -and $_.name -ne $Commander })
   [void]$sb.AppendLine("EDHREC pool: $($pool.Count) identity-legal (owned $(@($pool|Where-Object{$_.owned}).Count)). Line = incl% syn [own|`$buy][GC] Name - type")
   $byRole=@{}; foreach($c in $pool){ $r=RoleFor $c.name $c.type_line; if(-not $byRole.ContainsKey($r)){$byRole[$r]=New-Object System.Collections.ArrayList}; [void]$byRole[$r].Add($c) }
   foreach($role in $ORD){ if(-not $byRole.ContainsKey($role)){continue}
     [void]$sb.AppendLine("`n## $($LBL[$role]) ($($byRole[$role].Count))")
     foreach($c in @($byRole[$role] | Sort-Object {[double]$_.inclusion_pct} -Descending)){
       $tag=$(if($c.owned){'own'}else{'$'+([math]::Round([double]$c.price_usd,2))}); if($c.is_gc){$tag+=' GC'}
       [void]$sb.AppendLine(("{0,4}% {1,5} [{2}] {3} - {4}" -f $c.inclusion_pct,$c.synergy,$tag,$c.name,$c.type_line)) }
   }
   $poolNames=@{}; foreach($c in $bs){ $poolNames[$c.name.ToLower()]=$true }
   $func=@('ramp','card-draw','spot-removal','board-wipe','protection','recursion','tutor','land')
   $off=@($ownedCards | Where-Object { $ci=@($_.color_identity); $ok=$true; foreach($x in $ci){ if($cmdCI -notcontains $x){$ok=$false} }
     $ok -and ($_.legal -ne 'banned') -and (-not $poolNames.ContainsKey($_.name.ToLower())) -and ($_.name -ne $Commander) -and ($_.type_line -notmatch 'Basic Land') -and ($_.type_line -notmatch 'Token') })
   [void]$sb.AppendLine("`n# Owned, in identity, NOT in EDHREC pool - functional staples only (theme synergy: grep owned-cards.json)")
   $byRole2=@{}; foreach($c in $off){ $r=Get-Role $c.type_line $c.oracle_text; if($func -notcontains $r){continue}; if(-not $byRole2.ContainsKey($r)){$byRole2[$r]=New-Object System.Collections.ArrayList}; [void]$byRole2[$r].Add($c) }
   foreach($role in $func){ if(-not $byRole2.ContainsKey($role)){continue}
     [void]$sb.AppendLine("`n## $($LBL[$role]) ($($byRole2[$role].Count))")
     foreach($c in @($byRole2[$role] | Sort-Object {[double]$_.cmc})){ [void]$sb.AppendLine(("  {0} - {1}" -f $c.name,$c.type_line)) } }
   $outp=Join-Path $dir 'candidates.md'
   $sb.ToString() | Out-File -Encoding utf8 $outp
   "Wrote $outp ($([math]::Round((Get-Item $outp).Length/1KB,1)) KB) - read THIS to author the deck, not owned-cards.json."
 }

 'build' {
   if(-not $Commander){ throw 'build stage needs -Commander' }
   if(-not $Slug){ $Slug=Get-EdhrecSlug $Commander }
   $dir=Resolve-DataDir
   if(-not (Test-Path (Join-Path $SharedData 'owned-cards.json'))){ throw "No collection imported yet. Run '-Stage collection -CollectionCsv <your moxfield_haves.csv>' first (see ENGINE.md)." }
   $vfPath=Join-Path $dir 'variants.json'
   if(-not (Test-Path $vfPath)){ throw "No variants.json in '$dir'. Author the two builds first (the AI step: copy engine/handbuild.ps1, run it), then re-run build." }
   Ensure-GameChangers
   $vf=Read-Json $vfPath
   $fx=1.39; $fxp=Join-Path $SharedData 'fx.json'; $fxStale=$true
   if(Test-Path $fxp){ $fxj=Read-Json $fxp; if($fxj.usd_to_aud){ $fx=[double]$fxj.usd_to_aud }
     if($fxj.fetched){ try{ $fxStale=(((Get-Date)-[datetime]$fxj.fetched).TotalDays -gt 30) }catch{ $fxStale=$true } } }
   if($fxStale){ try{ $fr=Invoke-RestMethod -Uri 'https://open.er-api.com/v6/latest/USD' -Headers $UA -TimeoutSec 20
     if($fr.rates.AUD){ $fx=[double]$fr.rates.AUD; (@{usd_to_aud=$fx;fetched=(Get-Date).ToString('yyyy-MM-dd')}|ConvertTo-Json)|Out-File -Encoding utf8 $fxp } }catch{} }
   $gcSet=@{}; foreach($g in (Read-Json (Join-Path $SharedData 'game-changers.json'))){ $gcSet[$g.ToLower()]=$true }
   $ownedSet=@{}; foreach($o in (Read-Json (Join-Path $SharedData 'owned.json'))){ $n=$o.name.ToLower();$ownedSet[$n]=$true; if($n -match ' // '){$ownedSet[(($n -split ' // ')[0])]=$true} }
   $buildMap=@{}; foreach($b in (Read-Json (Join-Path $dir 'build-sheet.json'))){ $buildMap[$b.name.ToLower()]=$b }
   $ownedCards=Read-Json (Join-Path $SharedData 'owned-cards.json')
   $scry=@{}; foreach($c in $ownedCards){ $scry[$c.name.ToLower()]=$c }
   # reuse the fetch-stage Scryfall cache for non-owned candidates so we only fetch what's genuinely new
   foreach($f in @('candidates-cards.json','scryfall-cards.json')){ $p=Join-Path $dir $f; if(-not (Test-Path $p)){ $p=Join-Path $SharedData $f }
     if(Test-Path $p){ foreach($c in (Read-Json $p)){ $k=$c.name.ToLower(); if(-not $scry.ContainsKey($k)){ $scry[$k]=$c } } } }
   # gather names, fetch any still-missing (new buys not yet cached)
   $names=New-Object System.Collections.Generic.List[string]
   $names.Add($vf.commander)
   foreach($vk in $vf.variants.PSObject.Properties.Name){ $v=$vf.variants.$vk; foreach($c in $v.cards){$names.Add($c.name)}; foreach($c in $v.optionalBuys){$names.Add($c.name)} }
   if($vf.gcOptions){ foreach($g in $vf.gcOptions){ if($g.name){$names.Add($g.name)} } }   # GC picker menu - fetch any uncached
   $missing=@($names | Where-Object {$_ -and -not $scry.ContainsKey($_.ToLower())} | Select-Object -Unique)
   if($missing.Count){ $m=Get-ScryfallCards $missing; foreach($k in $m.Keys){ $scry[$k]=$m[$k] } }
   $cmdSc=$scry[$vf.commander.ToLower()]; $cmdCI=@(); if($cmdSc){$cmdCI=@($cmdSc.color_identity)}
   function Enrich($name,$role,$reason,$count){
     $sc=$scry[$name.ToLower()];$b=$buildMap[$name.ToLower()]; if(-not $count){$count=1}
     $cmc=0;$tl='';$mc='';$ora='';$ci=@();$price=$null;$img=$null;$imgS=$null;$legal='unknown'
     if($sc){$cmc=[double]$sc.cmc;$tl=$sc.type_line;$mc=$sc.mana_cost;$ora=$sc.oracle_text;$ci=@($sc.color_identity);if($sc.price_usd){$price=[double]$sc.price_usd};$img=$sc.image;$imgS=$sc.image_small;$legal=$sc.legal}
     if(-not $role){$role=Get-Role $tl $ora}
     $st='buy'; if($ownedSet.ContainsKey($name.ToLower())){$st='owned'}
     $incl=$null;$syn=$null; if($b){$incl=$b.inclusion_pct;$syn=$b.synergy}
     [pscustomobject]@{name=$name;role=$role;tags=(Get-Tags $tl $ora);status=$st;reason=$reason;count=$count;cmc=$cmc;type_line=$tl;mana_cost=$mc;oracle_text=$ora;color_identity=$ci;price_usd=$price;image=$img;image_small=$imgS;inclusion_pct=$incl;synergy=$syn;is_gc=$gcSet.ContainsKey($name.ToLower());legal=$legal}
   }
   function EnrichList($arr){ ,@($arr | ForEach-Object { Enrich $_.name $_.role $_.reason $_.count }) }
   $variants=[ordered]@{}
   foreach($vk in $vf.variants.PSObject.Properties.Name){ $v=$vf.variants.$vk; $vc=EnrichList $v.cards
     $variants[$vk]=[pscustomobject]@{label=$v.label;bracket=$v.bracket;buildType=$v.buildType;theme=$v.theme;wincons=$v.wincons;comboNotes=$v.comboNotes;howToPlay=$v.howToPlay;cards=$vc;optionalBuys=(EnrichList $v.optionalBuys);combos=(Get-Combos $vf.commander $vc)} }
   $cmd=Enrich $vf.commander 'commander' 'Your chosen commander.' 1
   # curated Game Changer menu -> enriched for the in-page GC picker (price/owned/image/synergy + is_gc verify)
   $gcOpts=@()
   if($vf.gcOptions){ foreach($g in $vf.gcOptions){ if(-not $g.name){continue}
     $e=Enrich $g.name $null $g.reason 1
     if(-not $e.is_gc){ Write-Warning "gcOptions: '$($g.name)' is not on the Game Changers list (kept anyway)." }
     $gcOpts+=$e } }
   # pool: owned cards legal in this commander's identity + all variant cards
   $poolMap=@{}
   function AddPool($sc){
     if(-not $sc){return}; $k=$sc.name.ToLower(); if($poolMap.ContainsKey($k)){return}
     # skip non-deck objects (tokens/emblems/etc.) that can leak in from a Moxfield export's token rows,
     # and anything without a real card supertype (e.g. type_line "Card") - they pollute the pool, the
     # Add-cards drawer, and the guide audit's name universe.
     $tl=''+$sc.type_line
     if($tl -match '\b(Token|Emblem|Dungeon|Scheme|Phenomenon|Vanguard|Conspiracy)\b'){return}
     if($tl -notmatch '\b(Creature|Land|Instant|Sorcery|Artifact|Enchantment|Planeswalker|Battle)\b'){return}
     $ci=@($sc.color_identity); foreach($col in $ci){ if($cmdCI -notcontains $col){return} }
     if($sc.legal -eq 'banned'){return}; if($sc.name -eq $vf.commander){return}
     $b=$buildMap[$k]; $pr=$null; if($sc.price_usd){$pr=[double]$sc.price_usd}
     $ip=$null;$sy=$null; if($b){$ip=$b.inclusion_pct;$sy=$b.synergy}
     # slim: store only the normal image - the small thumbnail URL is derived client-side (/normal/ -> /small/)
     $poolMap[$k]=[pscustomobject]@{name=$sc.name;role=(Get-Role $sc.type_line $sc.oracle_text);tags=(Get-Tags $sc.type_line $sc.oracle_text);type_line=$sc.type_line;cmc=[double]$sc.cmc;mana_cost=$sc.mana_cost;color_identity=$ci;price_usd=$pr;image=$sc.image;inclusion_pct=$ip;synergy=$sy;is_gc=$gcSet.ContainsKey($k);owned=$ownedSet.ContainsKey($k)}
   }
   foreach($c in $ownedCards){ AddPool $c }
   foreach($k in $scry.Keys){ AddPool $scry[$k] }
   # data-split: the small "deck" resource (commander + variants + fx) is separate from the big "pool"
   # so the page parses the deck instantly and only parses the pool when the Add-cards drawer first opens.
   $poolArr=@($poolMap.Values)
   # rev = a build stamp folded into the page's localStorage key, so a fresh build cleanly drops stale
   # in-browser edits (the deck loads from this pristine baseline) instead of silently overriding it.
   $rev=(Get-Date).ToString('yyyyMMddHHmmss')
   $out=[pscustomobject]@{commander=$cmd;defaultVariant=$vf.defaultVariant;variants=$variants;gcOptions=$gcOpts;fxAud=$fx;poolCount=$poolArr.Count;rev=$rev}
   # --- validate BEFORE writing: an illegal deck must NOT produce a deck-data.json ---
   $caps=@{1=0;2=0;3=3;4=999;5=999}
   $fail=New-Object System.Collections.ArrayList
   foreach($vk in $variants.Keys){ $v=$variants[$vk]; $cards=$v.cards
     $tot=($cards|ForEach-Object{ if($_.count){$_.count}else{1}}|Measure-Object -Sum).Sum
     $bad=@($cards|Where-Object{$_.color_identity|Where-Object{$cmdCI -notcontains $_}})
     $banned=@($cards|Where-Object{$_.legal -eq 'banned'})
     $gcc=@($cards|Where-Object{$_.is_gc}).Count
     $cap=$caps[[int]$v.bracket]; $capTxt=$cap; if($cap -gt 100){$capTxt='inf'}
     $line="[$vk] B$($v.bracket): $tot+cmd | GC=$gcc/$capTxt | combos=$($v.combos.Count) | CIbad=$($bad.Count) | banned=$($banned.Count)"
     if($bad.Count){ $line+=" >> ILLEGAL: $(@($bad|%{$_.name}) -join ', ')"; [void]$fail.Add("[$vk] off-identity: $(@($bad|%{$_.name}) -join ', ')") }
     if($banned.Count){ $line+=" >> BANNED: $(@($banned|%{$_.name}) -join ', ')"; [void]$fail.Add("[$vk] banned: $(@($banned|%{$_.name}) -join ', ')") }
     if(($tot+1) -ne 100){ [void]$fail.Add("[$vk] has $($tot+1) cards, not 100") }
     if($cap -le 100 -and $gcc -gt $cap){ [void]$fail.Add("[$vk] $gcc Game Changers exceed the Bracket $($v.bracket) cap of $cap") }
     $line }
   if($fail.Count){ throw "Validation FAILED - deck-data.json NOT written:`n  $(@($fail) -join "`n  ")" }
   Save-Json $out (Join-Path $dir 'deck-data.json')
   # always serialize the pool as a JSON ARRAY (PS5.1 ConvertTo-Json unwraps a 1-element array into a bare object)
   $poolJsonOut = if($poolArr.Count -eq 0){'[]'} elseif($poolArr.Count -eq 1){'['+($poolArr[0]|ConvertTo-Json -Depth 12 -Compress)+']'} else {$poolArr|ConvertTo-Json -Depth 12 -Compress}
   $poolJsonOut | Out-File -Encoding utf8 (Join-Path $dir 'pool-data.json')
   "Wrote deck-data.json + pool-data.json | pool=$($poolMap.Count)"
   # compact oracle dump for the MANDATORY fact-check step: one line per unique card across both builds,
   # so the guide can be checked against real Scryfall text WITHOUT reading the ~175 KB deck-data.json whole.
   try{
     $seen=@{}; $od=New-Object System.Text.StringBuilder
     [void]$od.AppendLine("# Oracle text - $($vf.commander). Fact-check howToPlay/wincons against THIS file, not memory.")
     [void]$od.AppendLine("# One line per unique card (commander + both builds). Format: Name [type_line] :: oracle (newlines -> ' / ').")
     $allCards=New-Object System.Collections.ArrayList; [void]$allCards.Add($cmd)
     foreach($vk in $variants.Keys){ foreach($c in $variants[$vk].cards){ [void]$allCards.Add($c) } }
     foreach($c in ($allCards | Sort-Object name)){
       $k=("$($c.name)").ToLower(); if($seen.ContainsKey($k)){ continue }; $seen[$k]=$true
       $o=("$($c.oracle_text)" -replace '\r?\n',' / ').Trim()
       [void]$od.AppendLine(("{0} [{1}] :: {2}" -f $c.name,$c.type_line,$o))
     }
     $odp=Join-Path $dir 'oracle.md'; $od.ToString() | Out-File -Encoding utf8 $odp
     "Wrote oracle.md ($([math]::Round((Get-Item $odp).Length/1KB,1)) KB, $($seen.Count) cards) - read THIS for the fact-check, not deck-data.json."
   }catch{ Write-Warning "oracle.md dump skipped (non-fatal): $($_.Exception.Message)" }
   # ---- GUIDE AUDIT (advisory) -> data/<slug>/audit.md : catches judgment-layer slips the mechanical
   #      validators miss. (A) a card NAMED in a build's guide prose that isn't actually in that build
   #      (the classic "I said Sun Titan but it's only in optimal" error); (B) detected combos blocked by
   #      an enabler prereq the deck can't meet (the Tayam + Devoted Druid mirage) - keep them out of the
   #      wincons. Advisory only (never blocks): a flag may be a deliberate "X does NOT work" mention or a
   #      cross-build comparison - but it turns "re-read every guide" into "check this short list".
   function Get-BlockingPrereq($prereq){
     if(-not $prereq){ return '' }
     $block=@(($prereq -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -and ($_ -match '\b(a|some|any|another) way to\b' -or $_ -match 'without (using|having)\b' -or $_ -match '\bable to\b' -or $_ -match 'some means to') })
     ($block -join ' ')
   }
   try{
     $known=@{}
     foreach($p in $poolArr){ if($p.name){ $known[$p.name]=$true } }
     foreach($avk in $variants.Keys){ foreach($c in $variants[$avk].cards){ $known[$c.name]=$true } }
     $basics=@('Forest','Plains','Swamp','Island','Mountain')
     $knownNames=@($known.Keys | Where-Object { $basics -notcontains $_ })
     $aud=New-Object System.Text.StringBuilder
     [void]$aud.AppendLine("# Guide audit - $($vf.commander)")
     [void]$aud.AppendLine('# Advisory. Review each flag; not all are errors (a deliberate "X does NOT work" mention or a comparison to another build is fine).')
     $totalFlags=0; $consoleLines=New-Object System.Collections.Generic.List[string]
     foreach($avk in $variants.Keys){
       $av=$variants[$avk]
       $inb=@{}; foreach($c in $av.cards){ $inb[$c.name]=$true }; $inb[$vf.commander]=$true
       $ah=$av.howToPlay
       $prose=(@($av.theme,$ah.win,$ah.keep,$ah.early,$ah.mid,$ah.late,$ah.style)+@($av.wincons)+@($av.comboNotes)) -join "`n"
       $mentNot=New-Object System.Collections.Generic.List[string]
       foreach($name in $knownNames){
         if($inb.ContainsKey($name)){ continue }
         if([regex]::IsMatch($prose, ('(?<![A-Za-z])'+[regex]::Escape($name)+'(?![A-Za-z])'))){ [void]$mentNot.Add($name) }
       }
       $blocked=New-Object System.Collections.Generic.List[string]
       foreach($co in @($av.combos)){ $bp=Get-BlockingPrereq $co.prereq; if($bp){ [void]$blocked.Add(((@($co.cards|ForEach-Object{$_.name}) -join ' + ')+"  -> needs: $bp")) } }
       [void]$aud.AppendLine("`n## [$avk] $($av.label)")
       if($mentNot.Count){ $totalFlags+=$mentNot.Count; $msg="REVIEW [$avk]: guide names $($mentNot.Count) card(s) NOT in this build: $((@($mentNot)) -join ', ')"; [void]$aud.AppendLine($msg); [void]$consoleLines.Add($msg) }
       else { [void]$aud.AppendLine("OK: every card named in the guide is in this build.") }
       if($blocked.Count){ [void]$aud.AppendLine("Detected combos blocked by an unmet prereq (keep these OUT of the wincons):"); foreach($b in $blocked){ [void]$aud.AppendLine("   - $b"); [void]$consoleLines.Add("BLOCKED [$avk]: $b") } }
     }
     $audp=Join-Path $dir 'audit.md'; $aud.ToString() | Out-File -Encoding utf8 $audp
     if($totalFlags){ "Guide audit: $totalFlags card-mention flag(s) to review -> $audp" } else { "Guide audit: clean - every card named in each guide is in that build -> $audp" }
     foreach($cl in $consoleLines){ "   $cl" }
   }catch{ Write-Warning "guide audit skipped (non-fatal): $($_.Exception.Message)" }
 }

 'inject' {
   if(-not $Commander){ throw 'inject stage needs -Commander' }
   if(-not $Slug){ $Slug=Get-EdhrecSlug $Commander }
   $dir=Resolve-DataDir
   $decksDir=Join-Path $Root 'decks'; New-Item -ItemType Directory -Force $decksDir | Out-Null
   $tpl=Get-Content (Join-Path $PSScriptRoot 'deckbuilder-template.html') -Raw -Encoding UTF8
   $json=Get-Content (Join-Path $dir 'deck-data.json') -Raw -Encoding UTF8
   $poolJson=Get-Content (Join-Path $dir 'pool-data.json') -Raw -Encoding UTF8
   # the JSON is spliced raw into inline <script> blocks; neutralize a stray </script> and the U+2028/2029 JS line terminators
   $json=$json.Replace('</','<\/'); $poolJson=$poolJson.Replace('</','<\/').Replace([string][char]0x2028,' ').Replace([string][char]0x2029,' ')
   $json=$json.Replace([string][char]0x2028,' ').Replace([string][char]0x2029,' ')
   $safeName=($Commander -replace "[^A-Za-z0-9]+",'-') -replace '(^-+|-+$)',''
   $html=Join-Path $decksDir "$safeName.html"
   $tpl.Replace('__DECK_DATA_PLACEHOLDER__',$json).Replace('__POOL_DATA_PLACEHOLDER__',$poolJson).Replace('__MANA_SPRITE__',(Get-ManaSprite)) | Out-File -Encoding utf8 $html
   # Moxfield-importable .txt per build (deck-<slug>-<key>.txt), plus deck-<slug>.txt for the default
   $dd=$json | ConvertFrom-Json
   $TYPES=@('Creatures','Sorceries','Instants','Artifacts','Enchantments','Planeswalkers','Battles','Lands','Other')
   function CType($t){ if($t -match 'Land'){'Lands'}elseif($t -match 'Creature'){'Creatures'}elseif($t -match 'Planeswalker'){'Planeswalkers'}elseif($t -match 'Battle'){'Battles'}elseif($t -match 'Instant'){'Instants'}elseif($t -match 'Sorcery'){'Sorceries'}elseif($t -match 'Artifact'){'Artifacts'}elseif($t -match 'Enchantment'){'Enchantments'}else{'Other'} }
   function MoxText($dv){
     $sb=New-Object System.Text.StringBuilder
     [void]$sb.AppendLine('Commander'); [void]$sb.AppendLine("1 $($dd.commander.name)"); [void]$sb.AppendLine(''); [void]$sb.AppendLine('Deck')
     foreach($t in $TYPES){ $dv.cards | Where-Object { (CType $_.type_line) -eq $t } | Sort-Object {[double]$_.cmc}, name | ForEach-Object { [void]$sb.AppendLine("$($_.count) $($_.name)") } }
     $sb.ToString()
   }
   $written=@()
   foreach($vk in $dd.variants.PSObject.Properties.Name){
     $p=Join-Path $decksDir "deck-$Slug-$vk.txt"; (MoxText $dd.variants.$vk) | Out-File -Encoding utf8 $p; $written+=$p
   }
   $defTxt=Join-Path $decksDir "deck-$Slug.txt"; (MoxText $dd.variants.($dd.defaultVariant)) | Out-File -Encoding utf8 $defTxt; $written+=$defTxt
   # record this deck in the manifest + regenerate the front-door index.html
   $dv0=$dd.variants.($dd.defaultVariant)
   $ownedCt=[int](@($dv0.cards | Where-Object { $_.status -eq 'owned' } | ForEach-Object { if($_.count){$_.count}else{1} } | Measure-Object -Sum).Sum) + $(if($dd.commander.status -eq 'owned'){1}else{0})
   $buyCt=[int](@($dv0.cards | Where-Object { $_.status -eq 'buy' } | ForEach-Object { if($_.count){$_.count}else{1} } | Measure-Object -Sum).Sum)
   Upsert-Deck ([ordered]@{ slug=$Slug; name=$Commander; file=('decks/'+(Split-Path $html -Leaf)); image=$dd.commander.image;
     identity=@($dd.commander.color_identity); builds=@($dd.variants.PSObject.Properties.Name); defaultBuild=$dd.defaultVariant;
     ownedCount=$ownedCt; buyCount=$buyCt; bracket=$dv0.bracket; theme=$dv0.theme; comboCount=[int](@($dv0.combos).Count); builtAt=(Get-Date).ToString('yyyy-MM-dd') })
   Update-Home
   "Wrote $html"
   $written | ForEach-Object { "Wrote $_" }
   "Updated index.html + data/decks.json"
 }

 'home' {
   Update-Home
   "Regenerated index.html from data/decks.json"
 }
}
