<#
  HAND-AUTHORED builds for Tayam, Luminous Enigma (the AI deckbuilding step) - and the copy-me TEMPLATE
  for new commanders: copy to handbuild-<slug>.ps1, change $commander + the card lists + play metadata.
  Writes data/<slug>/variants.json (slug auto-derived from $commander) with exactly TWO Bracket-3 decks:
    owned   = "Fully owned"  - the best deck from the collection right now (0 buys)
    optimal = "Optimal"      - the best Bracket-3 deck = owned + the buys worth making,
                               excluding the silly cEDH chase cards (no price cap otherwise)
  Each card carries a one-line "why it's here" reason. Lands include basics with counts.
  After running this: engine -Stage build (enrich + Spellbook combos + validate) then -Stage inject.

  Both decks are Bracket 3: <=3 Game Changers, no mass land denial, late-game 2-3 card combos OK.
    owned   GC = Smothering Tithe, Farewell, Crop Rotation
    optimal GC = Smothering Tithe, Demonic Tutor, Survival of the Fittest
#>
param([string]$Root)
$ErrorActionPreference='Stop'
# Workspace resolution mirrors the engine: -Root > $env:MTG_WORKSPACE > engine parent.
if(-not $Root){ if($env:MTG_WORKSPACE){ $Root=$env:MTG_WORKSPACE } else { $Root = Split-Path -Parent $PSScriptRoot } }
$data = Join-Path $Root 'data'
$commander = 'Tayam, Luminous Enigma'
# slug auto-derived from $commander (matches the engine's Get-EdhrecSlug); variants.json -> data/<slug>/
$slug = $commander.ToLowerInvariant()
$slug = ($slug.Normalize([Text.NormalizationForm]::FormD) -replace '\p{Mn}','')
$slug = $slug -replace '[^a-z0-9]+','-' -replace '(^-+|-+$)',''
$outDir = Join-Path $data $slug
New-Item -ItemType Directory -Force $outDir | Out-Null

function Parse([string]$txt){
  $out = New-Object System.Collections.ArrayList
  foreach($line in ($txt -split "`r?`n")){
    $l = $line.Trim(); if(-not $l){ continue }
    $p = $l -split '\s*\|\s*'
    $o = [ordered]@{ name = $p[0].Trim(); count = 1 }
    if($p.Length -ge 2 -and $p[1]){ $o.reason = $p[1].Trim() }
    if($p.Length -ge 3 -and $p[2]){ $o.count = [int]$p[2].Trim() }
    [void]$out.Add([pscustomobject]$o)
  }
  $out.ToArray()
}
function Total($a){ ($a | ForEach-Object { if($_.count){ $_.count } else { 1 } } | Measure-Object -Sum).Sum }

# ---------------------------------------------------------------- FULLY OWNED
$ownedNonland = @'
Sol Ring | Premier turn-one acceleration and a cheap artifact Tayam can recur.
Arcane Signet | Two-color fixing on turn two for a three-color commander.
Birds of Paradise | One-mana dork that fixes all three colors and can carry counters.
Llanowar Elves | Turn-one green dork and a cheap recursion target for Tayam.
Elvish Mystic | Redundant turn-one mana dork to power out Tayam.
Bloom Tender | Taps for one mana of each color among your permanents - huge in Abzan.
Priest of Titania | Explosive Elf-count ramp to fuel Tayam's activations.
Elvish Archdruid | Anthems your Elves and taps for a pile of green mana.
Selvala, Heart of the Wilds | Big mana and card draw off your fattest creatures.
Dryad of the Ilysian Grove | Ramp, fixing and an extra land drop to smooth three colors.
Solemn Simulacrum | Ramps, fixes, draws on death and trades in as sacrifice fodder.
Smothering Tithe | Snowballing white ramp (Game Changer); Treasures fund Tayam's {3} ability.
Nature's Lore | Fetches any Forest, including your shock duals, untapped.
Cultivate | Ramps and fixes while banking a land in hand.
Wood Elves | Fetches a Forest dual and leaves a body to sacrifice or pump.
Oracle of Mul Daya | Extra land drops and card advantage off the top.
Ramunap Excavator | Replays fetchlands and Crop Rotation lands every single turn.
Tireless Tracker | Turns spare lands into Clues and counters - relentless advantage.
Night's Whisper | Cheap, efficient two-card draw in black.
Read the Bones | Digs three deep and scries to smooth your draws.
Black Market Connections | Flexible cards, mana and Treasure - a repeatable advantage engine.
Garruk's Uprising | Draws when a big creature enters and grants the team trample.
Inspiring Call | Draws for your counter creatures and protects them from a sweeper.
Cathars' Crusade | Counters every creature on each ETB - the deck's engine and combo core.
Good-Fortune Unicorn | Puts a +1/+1 counter on each creature that enters, feeding Tayam.
Anafenza, Kin-Tree Spirit | Bolsters whenever a nontoken creature enters - steady free counters.
Mazirek, Kraul Death Priest | Every sacrifice grows your whole board with counters.
Rishkar, Peema Renegade | Hands out counters and turns your dorks into mana.
Branching Evolution | Doubles every +1/+1 counter you place - explosive with the engines.
Pollenbright Druid | Proliferates to spread counters across your whole board.
Metastatic Evangel | Converts your spellcasting into a growing counter engine.
Nessian Hornbeetle | Cheap counter aggro that snowballs on your big turns.
Puppeteer Clique | Persist makes it removal-resistant and a repeatable Tayam target; its ETB borrows creatures from graveyards for a turn (sac them before end of turn for value). A value/recursion body - it does NOT loop here, since the owned build runs no free repeatable sac outlet (that infinite is the Optimal build's trick).
Wildwood Scourge | A hydra that grows with the deck's counters and shares them out.
Kalonian Hydra | Doubles all your +1/+1 counters and closes games fast.
Basking Broodscale | Enters with counters and spawns 0/1 Eldrazi Spawn when counters are placed - infinite with Cathars' Crusade.
Slimefoot, the Stowaway | Makes Saproling fodder and drains as they die - your aristocrat backbone.
Bastion of Remembrance | Drains each opponent whenever your creatures die.
Eternal Witness | Buys back any spell; a premium MV-3 Tayam recursion target.
Sevinne's Reclamation | Returns an MV-3-or-less permanent and can flash back later.
Victimize | Reanimates two creatures for a single sacrifice - explosive tempo.
Buried Alive | Stocks the graveyard with three creatures for Tayam to return.
Final Parting | Tutors any card to hand and bins another for Tayam to recur.
Together Forever | Recurs your counter creatures and protects them from removal.
Recruiter of the Guard | Tutors any low-toughness creature - your toolbox finder.
Skyclave Apparition | Exiles a problem permanent on a recurrable body.
Acidic Slime | Destroys an artifact, enchantment or land on a recurrable body.
Reclamation Sage | Naturalizes a problem permanent and leaves a creature behind.
Overrun | Turns your wide counter board into a one-shot kill.
Swords to Plowshares | The most efficient white removal in the game.
Path to Exile | One-mana exile for any creature.
Assassin's Trophy | Answers any permanent at instant speed.
Anguished Unmaking | Exiles any nonland permanent - catches commanders and enchantments.
Go for the Throat | Clean two-mana creature kill.
Beast Within | Green catch-all that destroys any permanent.
Generous Gift | White catch-all removal for anything.
Crop Rotation | Sacrifices a land to fetch any land - grab Phyrexian Tower or Bojuka Bog (Game Changer).
Farewell | Modal exile sweeper (Game Changer) - wipe exactly what you need to.
Austere Command | Four-mode board wipe you can aim around your own board.
Kindred Dominance | Name a type you flood the board with for a near one-sided wipe.
Akroma's Will | Team-wide protection or a surprise lethal alpha strike.
Swiftfoot Boots | Haste and hexproof to protect Tayam from removal.
Sylvan Safekeeper | Protects your whole board from targeted removal for free.
'@

$ownedLands = @'
Command Tower | Enters untapped, taps for all three colors.
Exotic Orchard | Usually taps for any color you need in a multiplayer pod.
Path of Ancestry | Tri-land fixing plus a scry when you tap for a creature spell.
Sandsteppe Citadel | Tapland that covers all three colors at once.
Overgrown Tomb | Black-green shock dual; fetchable and untapped.
Godless Shrine | White-black shock dual; fetchable and untapped.
Canopy Vista | Green-white dual, untapped if you have two-plus lands.
Sunlit Marsh | White-black fixing land.
Vernal Fen | Black-green fixing land.
Twilight Mire | Black-green filter land for double-pip turns.
Llanowar Wastes | Black-green painland that taps untapped.
Brushland | Green-white painland that taps untapped.
Shattered Sanctum | White-black slow dual.
Overgrown Farmland | Green-white slow dual.
Scoured Barrens | White-black tapland with a life buffer.
Jungle Hollow | Black-green tapland with a life buffer.
Blossoming Sands | Green-white tapland with a life buffer.
Windswept Heath | Fetches a Forest or Plains dual and fuels graveyard recursion.
Misty Rainforest | Fetches a Forest source and a shuffle for the top.
Bloodstained Mire | Fetches a Swamp source and stocks your fetch synergies.
Phyrexian Tower | A free sacrifice outlet on a land - turns a creature into two mana.
Bojuka Bog | Graveyard hate on a land to shut off rival recursion.
Urborg, Tomb of Yawgmoth | Makes every land a Swamp to fix your black pips.
Nesting Grounds | Moves a +1/+1 counter around your board each turn.
Forest | Basic green source - your most-needed color. | 5
Swamp | Basic black source for Tayam and the aristocrats. | 4
Plains | Basic white source for removal and protection. | 3
'@

# ------------------------------------------------------------------- OPTIMAL
$optNonland = @'
Sol Ring | Premier turn-one acceleration and a cheap artifact Tayam can recur.
Arcane Signet | Two-color fixing on turn two for a three-color commander.
Birds of Paradise | One-mana dork that fixes all three colors and can carry counters.
Llanowar Elves | Turn-one green dork and a cheap recursion target for Tayam.
Elvish Mystic | Redundant turn-one mana dork to power out Tayam.
Bloom Tender | Taps for one mana of each color among your permanents - huge in Abzan.
Smothering Tithe | Snowballing white ramp (Game Changer); Treasures fund Tayam's {3} ability.
Nature's Lore | Fetches any Forest, including your shock duals, untapped.
Cultivate | Ramps and fixes while banking a land in hand.
Wood Elves | Fetches a Forest dual and leaves a body to sacrifice or pump.
Dryad of the Ilysian Grove | Ramp, fixing and an extra land drop to smooth three colors.
Ashnod's Altar | Free sac outlet that makes mana - the core of the Tayam + Cathars' loop.
Phyrexian Altar | Free sac outlet for colored mana; combo redundancy with Ashnod's Altar.
Viscera Seer | One-mana free sac outlet with scry - the cheapest loop enabler.
Carrion Feeder | Free sac outlet that grows itself and fuels every aristocrat line.
Blood Artist | Drains one target player on every death; Zulaport/Cruel Celebrant/Bastion are the each-opponent drains that make the loop lethal table-wide.
Zulaport Cutthroat | Redundant Blood Artist so one removal spell can't stop the drain.
Cruel Celebrant | A third drain-on-death body for combo redundancy.
Bastion of Remembrance | An enchantment Blood Artist that's hard to interact with.
Pitiless Plunderer | Treasure on every death pays for Tayam's {3} and enables mana loops.
Grave Pact | Each sacrifice you make wrecks every opponent's board.
Dictate of Erebos | Flash-in Grave Pact redundancy for the edict lock.
Midnight Reaper | Draws a card on each nontoken death to refuel the engine.
Cathars' Crusade | Counters every creature on each ETB - the deck's engine and combo core.
Good-Fortune Unicorn | Puts a +1/+1 counter on each creature that enters, feeding Tayam.
Anafenza, Kin-Tree Spirit | Bolsters whenever a nontoken creature enters - steady free counters.
Mazirek, Kraul Death Priest | Every sacrifice grows your whole board with counters.
Rishkar, Peema Renegade | Hands out counters and turns your dorks into mana.
Branching Evolution | Doubles every +1/+1 counter you place - explosive with the engines.
Devoted Druid | With Vizier of Remedies, taps for infinite green mana.
Vizier of Remedies | Removes Devoted Druid's drawback for infinite mana into Walking Ballista.
Walking Ballista | Infinite-mana and Mikaeus payoff, plus a counter-synergy removal piece.
Mikaeus, the Unhallowed | Team-wide undying and an infinite combo with Walking Ballista.
Karmic Guide | Reanimates a key creature; loops with Reveillark and a free sac outlet.
Reveillark | Returns your small creatures; a value loop with Karmic Guide and a sac outlet.
Sun Titan | Recurs an MV-3-or-less permanent on every attack - engine redundancy for Tayam.
Eternal Witness | Buys back any spell; a premium MV-3 Tayam recursion target.
Skyclave Apparition | Exiles a problem permanent on a recurrable body.
Recruiter of the Guard | Tutors a sac outlet, Blood Artist or other low-toughness piece.
Basking Broodscale | Enters with counters and spawns 0/1 Eldrazi Spawn when counters are placed - infinite tokens/mana with Cathars' Crusade.
Slimefoot, the Stowaway | Makes Saproling fodder and drains as they die.
Night's Whisper | Cheap, efficient two-card draw in black.
Read the Bones | Digs three deep and scries to smooth your draws.
Black Market Connections | Flexible cards, mana and Treasure - a repeatable advantage engine.
Inspiring Call | Draws for your counter creatures and protects them on the combo turn.
Skullclamp | Turns one-toughness fodder into two cards apiece - absurd advantage.
Kitchen Finks | Persist creature: with a free sac outlet (Ashnod's / Phyrexian Altar) + Cathars' Crusade + a drain payoff it loops for infinite drain, and gains you 2 life each bounce.
Swords to Plowshares | The most efficient white removal in the game.
Path to Exile | One-mana exile for any creature.
Assassin's Trophy | Answers any permanent at instant speed.
Anguished Unmaking | Exiles any nonland permanent - catches commanders and enchantments.
Go for the Throat | Clean two-mana creature kill.
Beast Within | Green catch-all that destroys any permanent.
Generous Gift | White catch-all removal for anything.
Austere Command | Four-mode board wipe you can aim around your own board.
Damnation | Clean four-mana wipe with no regeneration - a non-Game-Changer sweeper.
Kindred Dominance | Name a type you flood the board with for a near one-sided wipe.
Demonic Tutor | Finds any combo piece or answer (Game Changer).
Survival of the Fittest | Repeatable creature tutor that bins creatures for Tayam (Game Changer).
Final Parting | Tutors any card to hand and bins another for Tayam to recur.
Buried Alive | Stocks the graveyard with three creatures for Tayam to return.
Sevinne's Reclamation | Returns an MV-3-or-less permanent and can flash back later.
Heroic Intervention | Protects your whole board from a wipe or removal on the combo turn.
Akroma's Will | Team-wide protection or a surprise lethal alpha strike.
'@

$optLands = @'
Command Tower | Enters untapped, taps for all three colors.
Exotic Orchard | Usually taps for any color you need in a multiplayer pod.
Path of Ancestry | Tri-land fixing plus a scry when you tap for a creature spell.
Sandsteppe Citadel | Tapland that covers all three colors at once.
Overgrown Tomb | Black-green shock dual; fetchable and untapped.
Godless Shrine | White-black shock dual; fetchable and untapped.
Canopy Vista | Green-white dual, untapped if you have two-plus lands.
Sunlit Marsh | White-black fixing land.
Vernal Fen | Black-green fixing land.
Twilight Mire | Black-green filter land for double-pip turns.
Llanowar Wastes | Black-green painland that taps untapped.
Brushland | Green-white painland that taps untapped.
Shattered Sanctum | White-black slow dual.
Overgrown Farmland | Green-white slow dual.
Scoured Barrens | White-black tapland with a life buffer.
Jungle Hollow | Black-green tapland with a life buffer.
Blossoming Sands | Green-white tapland with a life buffer.
Windswept Heath | Fetches a Forest or Plains dual and fuels graveyard recursion.
Misty Rainforest | Fetches a Forest source and a shuffle for the top.
Bloodstained Mire | Fetches a Swamp source and stocks your fetch synergies.
Phyrexian Tower | A free sacrifice outlet on a land - turns a creature into two mana.
Bojuka Bog | Graveyard hate on a land to shut off rival recursion.
Urborg, Tomb of Yawgmoth | Makes every land a Swamp to fix your black pips.
Nesting Grounds | Moves a +1/+1 counter around your board each turn.
Forest | Basic green source - your most-needed color. | 4
Swamp | Basic black source for Tayam and the aristocrats. | 4
Plains | Basic white source for removal and protection. | 3
'@

$owned = @(Parse $ownedNonland) + @(Parse $ownedLands)
$opt   = @(Parse $optNonland)   + @(Parse $optLands)

# validate owned-build cards are actually in the collection
$ownedSet=@{}; foreach($o in (Get-Content (Join-Path $data 'owned.json') -Raw -Encoding UTF8 | ConvertFrom-Json)){ $n=$o.name.ToLower(); $ownedSet[$n]=$true; if($n -match ' // '){ $ownedSet[(($n -split ' // ')[0])]=$true } }
$notOwned = @($owned | Where-Object { -not $ownedSet.ContainsKey($_.name.ToLower()) })
if($notOwned.Count){ "WARNING - Fully-owned build references cards NOT in collection:"; $notOwned | ForEach-Object { "   $($_.name)" } }

"Fully owned : $(Total $owned) cards ($(@($owned).Count) lines)"
"Optimal     : $(Total $opt) cards ($(@($opt).Count) lines)"
$buys = @($opt | Where-Object { -not $ownedSet.ContainsKey($_.name.ToLower()) })
"Optimal buys: $($buys.Count) -> $((@($buys|ForEach-Object{$_.name})) -join ', ')"

# ------------------------------------------------------------------- play meta
$themeOwned = @'
100% from your collection: an Abzan +1/+1 counters, recursion and go-wide aristocrats midrange built around Tayam recurring your cheap permanents - with a real Basking Broodscale + Cathars' Crusade combo as a backup finish.
'@
$themeOpt = @'
The best Bracket 3 Tayam build - your collection plus the buys worth making. Adds free sacrifice outlets and drain payoffs for the Tayam + Cathars' Crusade loop, an infinite-mana line, and tutors for consistency.
'@

# --- OWNED how-to-play (verified against the decklist by the deckbuilding workflow) ---
$ownedWin = @'
This deck wins two ways and steers toward both at once. The RELIABLE plan is fair go-wide: ramp into a board of dorks and tokens, pump the whole team with Cathars' Crusade counters plus Branching Evolution / Kalonian Hydra / Good-Fortune Unicorn, then end the game in one attack with Overrun (team +3/+3 and trample) or Akroma's Will (flying, vigilance, double strike, plus lifelink, indestructible, and protection from each color when you choose both as commander) - that alpha strike, not the board sitting there, is what reduces opponents to zero. The FASTER plan is your owned two-card combo, Basking Broodscale + Cathars' Crusade: each token entering makes Cathars put a +1/+1 counter on Broodscale, which makes Broodscale create another 0/1 Eldrazi Spawn, for infinite ETBs, tokens, and counters. That alone makes no damage. To actually win you need Bastion of Remembrance already in play AND you must sacrifice each Spawn (free, via its own 'Sacrifice this token: Add {C}') so every death drains each opponent for 1 - that infinite drain kills the table. Note Slimefoot, the Stowaway is NOT a payoff for this loop: it only triggers on Saproling deaths, and the tokens are Eldrazi Spawn. With the loop but no Bastion, dump a giant board, pass, and win next turn with Overrun. Tayam is the grind engine that carries the fair plan, recurring your value and aristocrat pieces every turn until you out-resource and out-attack the table.
'@
$ownedKeep = @'
Keep hands with 2-3 lands AND at least one ramp piece (Sol Ring, Arcane Signet, Birds of Paradise, Llanowar Elves, Elvish Mystic) so you can land Tayam on turn 3 and power his {3} activation. The ideal opener also has an engine seed or payoff to build toward - Cathars' Crusade, Bastion of Remembrance, or a creature to start going wide. Strongly favor hands that pair a combo half (Basking Broodscale, Cathars' Crusade, or Mazirek) with a tutor (Final Parting, Buried Alive, Recruiter of the Guard, Crop Rotation) or with Bastion. A hand with Broodscale plus a counter engine (Branching Evolution, which doubles counters, or Good-Fortune Unicorn, which adds one to each creature that enters) is a fine fair-plan keep even without the full combo. MULLIGAN: 0-1 land hands; no-dork three-landers with zero engine pieces; all-action hands with one land; and do NOT keep a hand just because it has a lone combo half (e.g. Broodscale only) with no ramp and no Bastion - that is a trap. A clean default keep: 2 lands + Sol Ring + a one-drop dork + a creature + a removal spell.
'@
$ownedEarly = @'
Turns 1-3: maximize mana and stay low-profile. Turn 1, land plus a one-mana dork (Birds of Paradise, Llanowar Elves, Elvish Mystic) or Sol Ring. Turn 2, land plus a two-mana ramp/draw piece (Arcane Signet, Nature's Lore, Cultivate, Wood Elves, Night's Whisper) - the land-fetchers fix your Abzan colors. Turn 3, cast Tayam, Luminous Enigma ({1}{W}{B}{G}). Priest of Titania and Elvish Archdruid scale hard on this elf-heavy board, so drop them early to power out Tayam plus a second spell; Smothering Tithe and Black Market Connections also snowball your mana. Once Tayam is out, every OTHER creature you make enters with a bonus vigilance counter - that is fuel for his activation, so just deploy creatures and bank counters; do not activate Tayam yet. Do NOT tip your hand: avoid slamming Cathars' Crusade into open mana turn 3 unless you can protect it or win soon. Hold up Swords to Plowshares / Path to Exile / Go for the Throat for a genuinely dangerous commander or mana dork.
'@
$ownedMid = @'
Turns 4-6 is your combo and engine window. Drop Cathars' Crusade so every creature ETB puts a +1/+1 counter on your whole team and each token snowballs the board. Get Bastion of Remembrance online if you are going for the combo kill (it is the only on-board drainer that triggers on these token deaths). Start using Tayam: pay {3}, remove three counters from among your creatures, mill 3 and reanimate a permanent of mana value 3 or less - rebuy Eternal Witness, a dead dork, Solemn Simulacrum, or a removal-creature; Good-Fortune Unicorn, Anafenza, Pollenbright Druid and Branching Evolution keep refueling counters. To assemble the combo, get Basking Broodscale + Cathars' Crusade both in play (or Broodscale + Mazirek, where the Spawn's own free sac outlet drives the loop). Tutor the missing piece: Final Parting fetches one to hand and one to the yard; Buried Alive bins creatures like Broodscale for Tayam or Victimize to reanimate (both only handle creatures - grab Bastion of Remembrance the normal way, then Tayam can rebuy it as an MV-3 permanent); Recruiter of the Guard fetches Broodscale (toughness 2 or less); Victimize / Sevinne's Reclamation / Eternal Witness rebuy a removed piece. CRITICAL: before you start the loop, confirm Bastion of Remembrance is on the battlefield (Slimefoot does NOT work - the tokens are Eldrazi Spawn, not Saprolings), or that you have Overrun plus a way through. The loop alone is not a kill. Hold Akroma's Will / Swiftfoot Boots / Sylvan Safekeeper to protect Tayam and the combo turn.
'@
$ownedLate = @'
Turn 7+: close the game, and CHECK THE BOARD FIRST. (1) If you have Basking Broodscale + Cathars' Crusade AND Bastion of Remembrance in play, go off: each Spawn entering makes Cathars put a counter on Broodscale, which makes another 0/1 Eldrazi Spawn (infinite ETBs, tokens, and counters); sacrifice each Spawn via its own 'Sacrifice this token: Add {C}' so every death triggers Bastion to drain each opponent for 1 until the table is dead. Broodscale + Mazirek + the Spawn's free sac does the same loop plus infinite colorless mana, but STILL needs Bastion to actually kill. (2) If you have the loop but no Bastion, dump a massive board, pass, and next turn cast Overrun (+3/+3 and trample to all) or Akroma's Will (double strike plus protection-from-each-color evasion) for the lethal alpha strike. (3) If NO combo assembled, this is your bread-and-butter win: a wide, counter-pumped board (stack Cathars' + Branching Evolution + Kalonian Hydra + Good-Fortune Unicorn) plus one Overrun or Akroma's Will is usually well over lethal trampling damage split across the table - that single attack ends it. Protect the turn you go off with Akroma's Will, Inspiring Call (draw + indestructible to your countered creatures), Sylvan Safekeeper (sac lands to give Broodscale/Tayam shroud), and Swiftfoot Boots. If an opponent assembles first, reset with Farewell / Austere Command / Kindred Dominance, then rebuild via Tayam recursion (he reanimates a dead Broodscale or Bastion, MV 3 or less) and re-combo.
'@
$ownedStyle = @'
Patient, grindy midrange combo-control that pretends to be a fair value deck, then either alpha-strikes or quietly assembles its two-card drain combo. You are the ramp player who always has more mana, more creatures, and more recursion than the table. Play to the board, protect Tayam, hold up interaction over flashy early plays, and never tip the combo until Bastion of Remembrance is safely down. Sequence so you never expose a winning piece to removal a turn before you can use it. Win through inevitability: even with no combo, Tayam's recursion plus go-wide pump grinds everyone out.
'@
$howOwned = [pscustomobject]@{ win=$ownedWin.Trim(); keep=$ownedKeep.Trim(); early=$ownedEarly.Trim(); mid=$ownedMid.Trim(); late=$ownedLate.Trim(); style=$ownedStyle.Trim() }

# --- OPTIMAL how-to-play (verified against the decklist by the deckbuilding workflow) ---
$optWin = @'
This deck wins two ways, and the FAIR plan is your default. FAIR (most games): build a wide creature board, pump it every turn with Cathars' Crusade +1/+1 counters, then either alpha-strike for lethal combat damage or grind the table out through aristocrat drain - repeatedly sacrifice and recur creatures with Tayam plus a sac outlet while a drain payoff bleeds the table - Zulaport Cutthroat, Cruel Celebrant, or Bastion of Remembrance each hit EVERY opponent for 1 on every death (Blood Artist drains one chosen player per death, still lethal across a long loop). COMBO (when it assembles): almost every loop here produces only infinite death/ETB triggers, which do NOTHING on their own - they win ONLY because a drain payoff already in play turns each death into life loss (Zulaport / Cruel Celebrant / Bastion hit each opponent; Blood Artist hits one chosen player) and drains the whole table to 0 over the infinite loop. The single exception is Walking Ballista + Mikaeus, the Unhallowed, which deals damage DIRECTLY and needs no payoff: you ping each opponent's face to 0. Hard rule: never start a sacrifice loop unless a drain payoff is already on the battlefield (or you have Ballista + Mikaeus).
'@
$optKeep = @'
Keep a hand with 2-3 lands plus (a) an early green source - a mana dork (Birds of Paradise, Llanowar Elves, Elvish Mystic) or a rock (Sol Ring, Arcane Signet) - AND (b) a way to spend that mana: a draw engine (Skullclamp, Midnight Reaper, Night's Whisper, Read the Bones) or a tutor (Demonic Tutor, Survival of the Fittest). The ideal keep casts Tayam by turn 3-4 with a creature or two already down to fuel his ability. You do NOT need a combo piece in hand - you tutor for those. Survival of the Fittest in the opener is an auto-keep; it singlehandedly assembles every combo over a few turns. A lone Blood Artist or sac outlet is a bonus, not a requirement. MULLIGAN: no-land hands, all-land hands, hands with zero green sources (your ramp is green-heavy), and pure two-card-combo hands with no board, no protection, and no backup - you get blown out with nothing left.
'@
$optEarly = @'
Turns 1-3 are about mana and bodies, nothing fancy. Turn 1: land + a one-mana dork (Birds, Llanowar, Mystic), or Sol Ring. Turn 2: land + ramp or draw - Arcane Signet, Nature's Lore, Cultivate, Night's Whisper, or a cheap creature. Smothering Tithe off any early Plains quietly snowballs your mana. Turn 3-4: cast Tayam if the board is safe - remember every OTHER creature now enters with a vigilance counter, and those counters are FUEL for Tayam's ability, so deploy small creatures freely. Get Skullclamp down and equip it to a 1-toughness dork (Birds, Mystic): it draws 2 cards for 1 mana the moment that creature dies - your best engine. Hold up Swords to Plowshares / Path to Exile for a turn-1/2 mana rock or a scary commander. Don't tap out into open mana you can be punished into, and don't over-commit dorks if you fear a Damnation.
'@
$optMid = @'
Turns 4-7 build the engine and find the kill. Resolve Cathars' Crusade: now every creature that enters puts a +1/+1 counter on ALL your creatures, so your board balloons and each Tayam reanimation (the returning creature is an enter trigger) grows everything. Start using Tayam - {3}, remove three counters from among your creatures to mill 3 and return a permanent of MV 3 or less from your graveyard to the battlefield - to recur Eternal Witness, Skyclave Apparition, a sac outlet, or a drain payoff every turn. Get a FREE sac outlet down (Viscera Seer / Carrion Feeder, or Ashnod's Altar / Phyrexian Altar which also make mana) and a drain payoff (Blood Artist, Zulaport Cutthroat). Find missing pieces: Survival of the Fittest pitches a creature to tutor any creature (Mikaeus, Karmic Guide, Reveillark, or a payoff), Demonic Tutor grabs anything, Final Parting / Buried Alive load the graveyard for Tayam to reanimate. Deploy Grave Pact / Dictate of Erebos so every sacrifice forces opponents to sac too - that alone dismantles boards. Hold Heroic Intervention or Akroma's Will against a wipe.
'@
$optLate = @'
Turn 7+ you close. CHECK FIRST: is a drain payoff (Blood Artist / Zulaport Cutthroat / Cruel Celebrant / Bastion of Remembrance) on the battlefield? If yes, any loop becomes lethal. Cleanest lines: (1) Basking Broodscale + Cathars' Crusade - a token enters, Cathars' puts a +1/+1 counter on Broodscale, which makes a 0/1 Eldrazi Spawn, whose ETB re-triggers Cathars' - infinite ETBs, tokens, counters and {C} (sac each Spawn for mana); with a drain payoff in play, sacrifice each Spawn so every death drains (Zulaport / Cruel Celebrant / Bastion hit each opponent) and the table dies. (2) Karmic Guide + Reveillark + free sac outlet - sac both repeatedly; Reveillark's leave trigger returns Karmic Guide (power 2 or less), Karmic Guide returns Reveillark; infinite death triggers drained out by your payoff. (3) Walking Ballista + Mikaeus, the Unhallowed - NO payoff needed: remove a +1/+1 counter to ping, Ballista hits 0 counters and dies, undying returns it with a counter, repeat; aim each ping at an opponent's face to take the table to 0. (4) Devoted Druid + Vizier of Remedies - Vizier prevents the -1/-1 untap counter, so Druid untaps free for infinite green mana; sink it into Walking Ballista cast for a huge X, then ping every opponent out - that is the actual kill. FAIR CLOSE if no combo shows: Cathars' Crusade has made your board huge - swing wide for lethal, or grind by sacrificing and recurring with Tayam + Viscera Seer / Carrion Feeder while Blood Artist / Bastion drains each opponent and Grave Pact / Dictate of Erebos strips their blockers. A board of 8 pumped creatures with one Blood Artist down ends the game over two or three sacrifice cycles. Hold Akroma's Will / Heroic Intervention for the combo or swing turn.
'@
$optStyle = @'
Grindy, creature-based midrange-combo. You are the engine deck: you go a little wider and a little longer than everyone else, build an inevitable value machine with Tayam and Cathars' Crusade, and either combo-drain the table when the pieces line up or simply outlast and overrun it. Patient and resilient - Tayam reanimates your engine piece by piece, so you recover through removal and wipes - but respect the table's interaction. Hold protection, never 'go off' into open mana or an untapped blue opponent, and never start a loop unless the payoff that actually wins (a drain effect, or Ballista + Mikaeus) is already on the battlefield.
'@
$howOpt = [pscustomobject]@{ win=$optWin.Trim(); keep=$optKeep.Trim(); early=$optEarly.Trim(); mid=$optMid.Trim(); late=$optLate.Trim(); style=$optStyle.Trim() }

$winconsOwned = @(
@'
Combo drain (primary): Basking Broodscale + Cathars' Crusade - each Eldrazi Spawn that enters makes Cathars put a +1/+1 counter on Broodscale, re-triggering it to make another 0/1 Spawn, for infinite ETBs/tokens/counters. THE KILL requires Bastion of Remembrance already in play AND sacrificing each Spawn (free, via its own 'Sacrifice this token: Add {C}') so every death drains each opponent for 1 = infinite drain = table dead. Slimefoot does NOT work (Saproling-only). With no Bastion it is just a giant board - finish with Overrun.
'@.Trim(),
@'
Combo drain (variant): Basking Broodscale + Mazirek, Kraul Death Priest - sacrificing a Spawn (its own free sac outlet, or Phyrexian Tower) triggers Mazirek to put a +1/+1 counter on each creature including Broodscale, making a new Spawn to sac again, for infinite deaths, counters, and colorless mana. Still needs Bastion of Remembrance in play to convert those deaths into lethal drain.
'@.Trim(),
@'
Go-wide alpha strike (fair plan and combo-without-payoff backup): a board pumped by Cathars' Crusade / Branching Evolution / Kalonian Hydra / Good-Fortune Unicorn, then Overrun (+3/+3 and trample to all) for one lethal swing, or Akroma's Will (flying, vigilance, double strike - and lifelink, indestructible, protection from each color if you choose both) to double damage and punch through blockers. Akroma's Will adds no stats; it wins by doubling existing board power and granting evasion.
'@.Trim(),
@'
Grind-and-recur aristocrat drip (no combo): with Bastion of Remembrance in play, every creature death - Tayam fodder, chump blocks, Phyrexian Tower / Victimize sacrifices - drains each opponent for 1, a slow inevitable clock that also feeds Mazirek counters, eventually closed by an Overrun swing. (Use Bastion, not Slimefoot, for non-Saproling deaths.)
'@.Trim()
)
$winconsOpt = @(
@'
FAIR / default: Cathars' Crusade pumps a wide board of creatures and tokens - swing for lethal combat damage, OR grind by repeatedly sacrificing and recurring creatures (Tayam + Viscera Seer / Carrion Feeder) while Zulaport Cutthroat / Cruel Celebrant / Bastion of Remembrance drain each opponent 1 on every death (Blood Artist instead drains one chosen player); Grave Pact / Dictate of Erebos forces them to sac blockers alongside.
'@.Trim(),
@'
Basking Broodscale + Cathars' Crusade = infinite Eldrazi Spawn, ETBs, +1/+1 counters and colorless mana (each Spawn sacs for {C}). The PAYOFF that wins is a drain on board - sacrifice each Spawn so Zulaport / Cruel Celebrant / Bastion drain each opponent to 0 (Blood Artist drains one chosen player per death). Without a payoff it is just a giant board - pivot to an Overrun/Akroma's Will swing.
'@.Trim(),
@'
Karmic Guide + Reveillark + a free sac outlet = infinite recursion and death triggers; converts to a win ONLY through a drain payoff (Blood Artist / Zulaport / Cruel Celebrant / Bastion) - that drain on each death empties the table to 0.
'@.Trim(),
@'
Walking Ballista + Mikaeus, the Unhallowed = infinite undying pings dealt DIRECTLY to each opponent's face (NO payoff needed). Alternatively, Devoted Druid + Vizier of Remedies makes infinite green mana to cast Walking Ballista for a lethal X and ping the whole table out.
'@.Trim()
)
$comboOwned = @(
  'Bracket 3: three Game Changers (Smothering Tithe, Crop Rotation, Farewell), no mass land denial. Your owned 2-card combo is Basking Broodscale + Cathars'' Crusade (infinite tokens / death triggers) - convert with Bastion of Remembrance or Slimefoot drain, or an Overrun swing. Basking Broodscale + Mazirek loops too.',
  'These are late-game, board-dependent lines - keep a fair back-up plan and protect the turn. The Optimal build adds free sac outlets and dedicated drain payoffs to make the loop far more reliable.'
)
$comboOpt = @(
  'Bracket 3: three Game Changers (Smothering Tithe, Demonic Tutor, Survival of the Fittest), late-game 2-3 card combos only, no mass land denial.',
  'Hold combo pieces until you can protect the turn (Heroic Intervention / Akroma''s Will / Swiftfoot Boots).'
)

$variants = [ordered]@{
  owned = [pscustomobject]@{
    label='Fully owned'; bracket=3; buildType='owned'; theme=$themeOwned.Trim();
    wincons=$winconsOwned; comboNotes=$comboOwned; howToPlay=$howOwned; cards=$owned; optionalBuys=@()
  }
  optimal = [pscustomobject]@{
    label='Optimal'; bracket=3; buildType='optimal'; theme=$themeOpt.Trim();
    wincons=$winconsOpt; comboNotes=$comboOpt; howToPlay=$howOpt; cards=$opt; optionalBuys=@()
  }
}
$out = [pscustomobject]@{ commander=$commander; defaultVariant='owned'; variants=$variants }
$out | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 (Join-Path $outDir 'variants.json')
"Wrote $outDir\variants.json (owned + optimal)."
