<#
  HAND-AUTHORED builds for Tayam, Luminous Enigma (the AI deckbuilding step) - and the copy-me TEMPLATE
  for new commanders: copy to handbuild-<slug>.ps1, change $commander + the card lists + play metadata.
  Writes data/<slug>/variants.json (slug auto-derived from $commander) with TWO Bracket-3 decks + a GC menu:
    owned   = "Fully owned"  - the best deck from the collection right now (0 buys)
    optimal = "Optimal"      - the genuinely-best Bracket-3 deck: START FROM THE cEDH LIST and STRIP the
                               super-expensive + Game Changer cards (fast mana, dual lands, extra tutors)
                               down to a legal Bracket 3 (<=3 Game Changers, no chase). Inherits the real
                               cEDH combo skeleton - it is NOT just "EDHREC good-stuff". For Tayam that is a
                               commander-centric mill-reanimate engine (see ENGINE.md methodology).
  Each card carries a one-line "why it's here" reason. Lands include basics with counts.
  $gcPicks  = a curated shortlist of high-synergy Game Changers (name | reason) the engine enriches into
              deck-data.json -> D.gcOptions, which powers the in-page "Game Changers" picker (swap within
              the bracket's GC cap). These are the GC menu for the commander, not necessarily all in a build.
  After running this: engine -Stage build (enrich + Spellbook combos + validate) then -Stage inject.

  Both builds are Bracket 3: <=3 Game Changers, no mass land denial, late-game 2-3 card combos OK.
    owned   GC = Smothering Tithe, Farewell, Crop Rotation
    optimal GC = Smothering Tithe, Survival of the Fittest, Demonic Tutor
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

# ------------------------------------------------------------------- OPTIMAL  (cEDH list stripped to Bracket 3)
# A cEDH Tayam list with the fast mana / dual lands / extra Game-Changer tutors stripped out to a legal B3.
# It keeps the real cEDH skeleton: Tayam as a Gitrog-style mill-reanimate engine (self-mill stocks cheap
# creatures, Tayam recurs them), the counter package that fuels his {3}, and the strong on-theme combos
# (Walking Ballista + Devoted Druid/Vizier infinite mana, Ballista + Mikaeus + a sac outlet, the persist loop).
$optNonland = @'
Sol Ring | Turn-one acceleration; the extra mana powers repeated {3} Tayam activations.
Arcane Signet | Fixes Abzan and helps you hit Tayam's activation on curve.
Birds of Paradise | One-mana any-color dork and a cheap body to recur and resacrifice.
Llanowar Elves | Turn-one green dork; trivially rebought by Tayam if it dies.
Elvish Mystic | Redundant turn-one dork to land Tayam early and fund his ability.
Priest of Titania | Scales with your wide elf/creature board into the mana that fuels endless {3} activations.
Bloom Tender | Two-mana dork that taps for a huge chunk of Abzan mana once Tayam and friends are down.
Devoted Druid | An Elf mana dork that makes infinite green with Vizier of Remedies - pour it into Walking Ballista to win; an MV-2 body Tayam happily reanimates.
Green Sun's Zenith | Tutors any green creature straight onto the battlefield (Devoted Druid, Dryad, a dork, a payoff) - premium toolbox consistency.
Sakura-Tribe Elder | Chump, ramp, and a perfect MV-2 body to sacrifice and recur for value.
Dryad of the Ilysian Grove | Ramp + fixing on an MV-3 body Tayam happily reanimates each turn.
Cathars' Crusade | THE engine: every creature ETB puts a +1/+1 counter on each creature you control, refilling Tayam's fuel faster than he spends it - the core of the loop.
Good-Fortune Unicorn | Each creature you make enters with a +1/+1 counter, doubling up with Tayam's vigilance counter as activation fuel.
Rishkar, Peema Renegade | Drops +1/+1 counters and turns your counter-laden creatures into mana dorks to power Tayam.
Winding Constrictor | Adds one to every counter you'd place - turbocharges Cathars/Tayam fuel generation.
Hardened Scales | One-mana counter multiplier; makes the Cathars loop counter-positive even on a small board.
Branching Evolution | Doubles every +1/+1 counter placed, so each Cathars trigger more than refunds a Tayam activation.
Mazirek, Kraul Death Priest | Every permanent you sacrifice puts a +1/+1 counter on each creature - a second counter engine that feeds Tayam off your sac outlets.
Tyvar, Jubilant Brawler | A second Tayam: its -2 mills three and reanimates an MV-2-or-less creature, and its static gives your creatures haste so a freshly-recurred dork taps at once; Tayam can rebuy it (MV-3 permanent).
Viscera Seer | Free sac outlet; loops with Tayam recursion and turns Walking Ballista + Mikaeus into infinite pings.
Carrion Feeder | Free sac outlet that grows on counters - sacrifice, recur with Tayam, repeat, and the outlet for the Ballista + Mikaeus loop.
Ashnod's Altar | Free sac outlet that makes {C}{C} per creature - the mana half of the infinite Tayam drain loop (and of Ballista + Mikaeus).
Blood Artist | Drains each opponent on every creature death - the payoff that turns the Tayam loop lethal.
Zulaport Cutthroat | Redundant Blood Artist; each looped death drains the table by one.
Bastion of Remembrance | On-board drain that Tayam can itself reanimate (MV 3) - the most resilient payoff for the loop.
Elas il-Kor, Sadistic Pilgrim | Drains on death AND pings on your own ETBs, so the Tayam reanimation loop bleeds the table from both ends.
Pitiless Plunderer | Makes a Treasure on each creature death - the third mana per loop that lets Ashnod's Altar fully pay Tayam's {3}.
Vizier of Remedies | Removes Devoted Druid's untap drawback for infinite green mana, and stops -1/-1 counters hurting your team; an MV-3 Tayam target.
Walking Ballista | An MV-0 Tayam reanimation target, a +1/+1-counter payoff, repeatable removal, and the sink for infinite mana - your cleanest direct-damage kill.
Mikaeus, the Unhallowed | Gives your non-Humans +1/+1 and undying (free counters + resilience), and combos with Walking Ballista plus a free sac outlet for infinite pings.
Eternal Witness | Premium MV-3 target: rebuy any spell from the yard every time Tayam returns it.
Reclamation Sage | Recurring artifact/enchantment removal - reanimate it whenever the table plays a problem permanent.
Skyclave Apparition | Repeatable exile removal on an MV-3 body; Tayam turns it into a removal engine.
Ramunap Excavator | Lets you replay sacrificed/fetched lands; an MV-3 value body Tayam loves to return.
Weaponcraft Enthusiast | Fabricate 2 makes two bodies (or two +1/+1 counters) on an MV-3 reanimation target - sac fodder + counters that fuel Tayam's {3} and the Ashnod's Altar mill loop; the signature cEDH Tayam engine piece.
Recruiter of the Guard | Tutors any toughness-2-or-less creature (sac outlets, payoffs, combo pieces) to hand on ETB - re-buyable with Tayam.
Stitcher's Supplier | One-mana self-mill: mills three on ETB AND on death, stocking the graveyard with reanimation targets; sac it to a free outlet and Tayam rebuys it (MV 1) to mill again.
Kitchen Finks | Persist creature: with a free sac outlet (Viscera Seer / Carrion Feeder / Ashnod's Altar) + Cathars' Crusade it loops forever - Cathars' +1/+1 cancels persist's -1/-1 so it never stays dead - for infinite ETBs/deaths; add an aristocrat to drain the table. Also an MV-3 Tayam target that gains 2 life each bounce.
Victimize | Sacrifice one creature to reanimate two - explosive with cheap ETB bodies and a head start on the loop.
Wood Elves | MV-3 ETB ramp that fetches a Forest-type dual - a clean, repeatable Tayam reanimation target.
Buried Alive | Stocks the yard with three creatures for Tayam (or Victimize) to reanimate immediately.
Birthing Pod | Sacrifice a creature to fetch one a mana-value higher - chains your toolbox of ETB targets straight onto the battlefield.
Eldritch Evolution | Sac a creature to tutor a bigger one to the battlefield - finds a payoff or combo piece at instant value.
Survival of the Fittest | Game Changer creature-tutor engine: discard to find any combo piece, then reanimate it with Tayam - the deck's consistency backbone.
Final Parting | Tutors any card to hand and bins a second for Tayam to return - assembles the loop in one card.
Night's Whisper | Cheap two-card burst to keep the engine fed.
Read the Bones | Card draw with scry that also fills the yard for Tayam.
Satyr Wayfinder | Mills four and digs a land into hand on an MV-2 body Tayam can rebuy - fills the yard with creatures to reanimate.
Skullclamp | Turns your dorks and looped creatures into a card-draw furnace; absurd with free sac outlets.
Smothering Tithe | Game Changer ramp; Treasures snowball into the mana that fuels chained Tayam activations.
Swords to Plowshares | Best-in-class one-mana exile removal.
Path to Exile | One-mana exile to answer a threat or combo piece.
Go for the Throat | Efficient instant-speed creature kill.
Assassin's Trophy | Answers any permanent at instant speed.
Anguished Unmaking | Exiles any nonland permanent - flexible catch-all.
Beast Within | Destroys any permanent; the 3/3 is irrelevant when you out-grind it.
Generous Gift | Removes any permanent at instant speed for three mana.
Demonic Tutor | Unconditional any-card tutor (Game Changer) - finds the missing combo piece, a sac outlet, or an answer.
Austere Command | Flexible four-mode wipe you can angle to spare your own board.
Swiftfoot Boots | Hexproof + haste to protect Tayam and activate him the turn he lands.
Sylvan Safekeeper | Sac lands to give Tayam (or a combo piece) shroud through removal.
Heroic Intervention | Protects your whole board from a wipe or targeted removal on the combo turn.
Overrun | The fair-plan kill: a board fattened by counters swings for lethal with trample.
'@

$optLands = @'
Command Tower | Perfect Abzan fixing.
Overgrown Tomb | B/G shock dual, fetchable.
Godless Shrine | W/B shock dual, fetchable.
Sandsteppe Citadel | Abzan tri-land.
Canopy Vista | G/W dual that enters untapped with two basics.
Blossoming Sands | G/W gain-land fixing.
Jungle Hollow | B/G gain-land fixing.
Scoured Barrens | W/B gain-land fixing.
Shattered Sanctum | W/B slow/surveil dual.
Sunlit Marsh | W/B fixing.
Twilight Mire | B/G filter land.
Vernal Fen | B/G fixing.
Llanowar Wastes | B/G painland.
Brushland | G/W painland.
Path of Ancestry | Fixing + a free counter-friendly scry off your typed creatures.
Windswept Heath | Fetch for Forest/Plains types.
Misty Rainforest | Fetch for Forest sources.
Bloodstained Mire | Fetch for Swamp sources.
Wooded Foothills | Fetch that grabs your Forest duals.
Polluted Delta | Fetch for Swamp sources.
Fabled Passage | Budget fetch for any basic.
Phyrexian Tower | Sacrifice a creature for {B}{B} - a land-based sac outlet that feeds the loop.
Bojuka Bog | Graveyard hate stapled to a land.
Urborg, Tomb of Yawgmoth | Turns all lands into Swamps for black-heavy fixing.
Nesting Grounds | Moves a counter each turn - quietly tops up or redistributes Tayam fuel.
Forest | Basic green source. | 4
Plains | Basic white source. | 3
Swamp | Basic black source. | 4
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
A cEDH Tayam list stripped to a clean Bracket 3. Tayam is the engine AND the payoff: a low-curve Abzan shell that uses his {3} ability as a Gitrog-style mill-reanimate motor - mill three, bin cheap creatures, return one every turn - fuelled by Cathars' Crusade and a stack of +1/+1-counter multipliers that refill the ability faster than he spends it. Self-mill (Stitcher's Supplier, Satyr Wayfinder, Weaponcraft Enthusiast) stocks the graveyard with reanimation targets, Green Sun's Zenith and Tyvar, Jubilant Brawler add tutoring and a second mill-reanimate engine, and it runs the combos a Tayam deck wants: an infinite reanimation-drain loop through the commander, plus Walking Ballista fed by Devoted Druid + Vizier of Remedies infinite mana and by Mikaeus's undying. The cEDH fast mana, dual lands and extra Game-Changer tutors are stripped out to keep it Bracket 3. Almost every creature is MV 3 or less so Tayam can rebuild the deck after a wipe.
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

# --- OPTIMAL how-to-play (cEDH mill-reanimate plan; fact-checked against oracle.md) ---
$optWin = @'
Tayam is the heart of this deck: every creature you play banks a vigilance counter, Cathars' Crusade plus Winding Constrictor / Hardened Scales / Branching Evolution / Good-Fortune Unicorn pile on more, and Tayam's {3}-remove-three-counters ability is always fuelled to reanimate a permanent of mana value 3 or less every turn. You have three ways to close. (1) THE COMMANDER LOOP: Tayam + Cathars' Crusade + Ashnod's Altar + Pitiless Plunderer + an aristocrat (Blood Artist, Zulaport Cutthroat, Bastion of Remembrance, or Elas il-Kor) with at least three creatures out. Sacrifice a creature to Ashnod's Altar for {C}{C}; Pitiless Plunderer makes a Treasure (that is the third mana); pay Tayam's {3}, remove three counters, mill three, and return the creature. It re-enters, so Tayam gives it a vigilance counter and Cathars' Crusade puts a +1/+1 counter on EACH creature you control - more fuel than you spent - while the aristocrat drains on every death (Zulaport Cutthroat, Bastion of Remembrance and Elas il-Kor each hit every opponent; Blood Artist drains one player at a time). Repeat for infinite drain. (2) WALKING BALLISTA: Devoted Druid + Vizier of Remedies makes infinite green mana - pump it into Walking Ballista's '{4}: put a +1/+1 counter on this creature', then remove the counters to deal infinite damage to each opponent. Walking Ballista + Mikaeus, the Unhallowed also loops with any free sac outlet (Viscera Seer, Carrion Feeder, or Ashnod's Altar): sacrifice the 0-counter Ballista, undying returns it with a +1/+1 counter, remove it to ping, repeat. Both lines deal damage DIRECTLY and need no drain payoff. (3) THE FAIR PLAN: with no combo, use Tayam as a grindy mill-reanimate engine - each activation mills three (Stitcher's Supplier, Satyr Wayfinder and Weaponcraft Enthusiast stock the yard faster) and rebuys a value creature (Eternal Witness, Skyclave Apparition, a dork), so you dig and out-resource the table, then swing a counter-pumped board through Overrun for +3/+3 and trample. Most creatures here are mana value 3 or less, so Tayam rebuilds the bulk of your board after a wipe - the ones he can't return are the pricier payoffs (Mikaeus at MV 6, Mazirek and Pitiless Plunderer at MV 4).
'@
$optKeep = @'
Keep hands with 2-3 lands AND at least one green source - a mana dork (Birds of Paradise, Llanowar Elves, Elvish Mystic, Devoted Druid) or a rock (Sol Ring, Arcane Signet) - so you can land Tayam on turn 3 and start activating. The best openers add a counter-engine seed (Cathars' Crusade, Good-Fortune Unicorn) or a tutor (Survival of the Fittest, Green Sun's Zenith, Demonic Tutor, Final Parting). Survival of the Fittest or Green Sun's Zenith in the opener is an auto-keep - they assemble any combo over a few turns. You do NOT need a combo piece in hand; Tayam plus the tutors find them. MULLIGAN: 0-1 land hands; all-land hands; hands with no green source (your ramp is green-heavy); and lone-combo-piece hands with no mana and no board - that is a trap.
'@
$optEarly = @'
Turns 1-3: ramp and deploy small bodies, nothing fancy. Turn 1, land plus a one-mana dork (Birds of Paradise, Llanowar Elves, Elvish Mystic) or Sol Ring. Turn 2, land plus a two-mana ramp/draw piece (Arcane Signet, Sakura-Tribe Elder, Night's Whisper) or a counter producer. Turn 3, cast Tayam, Luminous Enigma ({1}{W}{B}{G}). Once Tayam is down every OTHER creature enters with a vigilance counter - that is FUEL - so deploy creatures freely and bank counters; do not activate Tayam yet. Equip Skullclamp to a one-toughness dork (Birds, Mystic) to draw two cards when it dies - your best early engine. Hold Swords to Plowshares / Path to Exile / Go for the Throat for a dangerous dork or commander, and do not over-extend into a likely board wipe.
'@
$optMid = @'
Turns 4-6 build the engine. Resolve Cathars' Crusade so every creature ETB pumps your whole board, then start activating Tayam each turn - {3}, remove three counters from among your creatures, mill three, and return a permanent of mana value 3 or less: rebuy Eternal Witness, Skyclave Apparition, a sac outlet, an aristocrat, or a dead dork. Stitcher's Supplier and Satyr Wayfinder (plus Tayam's own mill and Tyvar, Jubilant Brawler's -2) keep stocking the graveyard with cheap creatures to reanimate, and Weaponcraft Enthusiast makes bodies and counters to keep the activations coming. Get a free sac outlet down (Viscera Seer / Carrion Feeder, or Ashnod's Altar which also makes mana) and a drain payoff (Blood Artist, Zulaport Cutthroat). Find the missing pieces: Survival of the Fittest discards a creature to tutor any creature, Green Sun's Zenith puts a green creature straight onto the battlefield, Demonic Tutor grabs anything; Birthing Pod / Eldritch Evolution sacrifice up the curve into a payoff; Final Parting / Buried Alive load the yard for Tayam; Recruiter of the Guard grabs a toughness-2 piece. If you draw a Walking Ballista half, hold it and assemble Devoted Druid + Vizier of Remedies, or Walking Ballista + Mikaeus + a free sac outlet. Hold Heroic Intervention / Swiftfoot Boots / Sylvan Safekeeper to protect the turn you go off.
'@
$optLate = @'
Turn 7+ you close - check the board first. (1) COMMANDER LOOP: with Cathars' Crusade + Ashnod's Altar + Pitiless Plunderer + an aristocrat and three-plus creatures out, sacrifice and reanimate with Tayam infinitely; each death drains the table to zero. (2) DEVOTED DRUID + VIZIER OF REMEDIES: Vizier prevents the -1/-1 untap counter, so Devoted Druid untaps free for infinite green mana - pour it into Walking Ballista ({4} to add a counter, then remove counters to ping) and shoot every opponent out, no payoff needed. (3) WALKING BALLISTA + MIKAEUS, THE UNHALLOWED + a free sac outlet (Viscera Seer / Carrion Feeder / Ashnod's Altar): sacrifice the 0-counter Ballista, undying returns it with a +1/+1 counter, remove it to ping for 1, sacrifice again - infinite pings (Ashnod's Altar as the outlet also makes infinite mana). (4) FAIR CLOSE: a board pumped by Cathars' Crusade, Branching Evolution and Rishkar swings lethal through Overrun, or grind with Tayam + a sac outlet while Blood Artist / Bastion of Remembrance drains. Protect with Swiftfoot Boots / Sylvan Safekeeper / Heroic Intervention; after a wipe, Tayam reanimates your engine (mana value 3 or less) and you re-assemble.
'@
$optStyle = @'
Patient engine-combo built around the commander - a cEDH list dialled back to Bracket 3. You are the deck with more mana, more creatures and more recursion than the table; Tayam grinds value every turn and rebuilds through removal, while the counter package quietly turns each activation counter-positive. Don't go off into open mana or an untapped blue player, hold protection for the combo turn, and remember the fair plan - a counter-pumped Overrun swing - is always there if the table breaks up your combos. Sequence so you never expose a key piece to removal a turn before you can use it.
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
Infinite Tayam drain (commander loop): Tayam + Cathars' Crusade + Ashnod's Altar + Pitiless Plunderer + an aristocrat (Blood Artist / Zulaport Cutthroat / Bastion of Remembrance / Elas il-Kor), with three-plus creatures out. Sacrifice a creature to Ashnod's Altar for {C}{C}, Pitiless Plunderer makes a Treasure = Tayam's {3}; reanimate the creature, Cathars' Crusade refunds a +1/+1 counter on each creature you control (more than the three spent), and the aristocrat drains on every death (Zulaport Cutthroat / Bastion of Remembrance / Elas il-Kor hit each opponent; Blood Artist drains one player at a time). Repeat = infinite drain = table dead.
'@.Trim(),
@'
Devoted Druid + Vizier of Remedies -> Walking Ballista: Vizier removes Devoted Druid's -1/-1 untap drawback, so it untaps for infinite green mana; pump Walking Ballista's '{4}: put a +1/+1 counter on this creature' and remove the counters to deal infinite damage to each opponent. Deals damage directly - no drain payoff needed.
'@.Trim(),
@'
Walking Ballista + Mikaeus, the Unhallowed + a free sac outlet (Viscera Seer / Carrion Feeder / Ashnod's Altar): Mikaeus's +1/+1 keeps Ballista alive at 0 counters, so use the outlet to kill it; undying returns it with a +1/+1 counter, remove it to ping for 1, sacrifice again - infinite pings to the table (Ashnod's Altar as the outlet also makes infinite mana).
'@.Trim(),
@'
Persist loop: Kitchen Finks + Cathars' Crusade + a free sac outlet (Viscera Seer / Carrion Feeder / Ashnod's Altar). Sacrifice Kitchen Finks; persist returns it with a -1/-1 counter; Cathars' Crusade puts a +1/+1 counter on each creature, and on Finks that cancels the -1/-1, so it can persist again - infinite ETBs and deaths (Ashnod's also makes infinite colorless mana). With an aristocrat in play (Blood Artist / Zulaport Cutthroat / Bastion of Remembrance / Elas il-Kor) the infinite deaths drain the table; Tayam can rebuy Finks (MV 3) if it is removed.
'@.Trim(),
@'
Go-wide fair plan (backup): a board fattened by Cathars' Crusade, Branching Evolution, Rishkar and Good-Fortune Unicorn swings for lethal with Overrun's +3/+3 and trample - the close when the table breaks up your combos. Tayam rebuilds the board through removal and wipes, so the fair plan is highly resilient.
'@.Trim()
)
$comboOwned = @(
  'Bracket 3: three Game Changers (Smothering Tithe, Crop Rotation, Farewell), no mass land denial. Your owned 2-card combo is Basking Broodscale + Cathars'' Crusade (infinite tokens / death triggers) - convert with Bastion of Remembrance or Slimefoot drain, or an Overrun swing. Basking Broodscale + Mazirek loops too.',
  'These are late-game, board-dependent lines - keep a fair back-up plan and protect the turn. The Optimal build adds free sac outlets and dedicated drain payoffs to make the loop far more reliable.'
)
$comboOpt = @(
  'Bracket 3: three Game Changers (Smothering Tithe, Survival of the Fittest, Demonic Tutor), no mass land denial, no extra-turn loops.',
  'This is a cEDH Tayam list stripped to Bracket 3 - the mill-reanimate engine plus the strong on-theme combos (Walking Ballista with Devoted Druid + Vizier infinite mana, Walking Ballista + Mikaeus + a free sac outlet, the Kitchen Finks + Cathars'' Crusade persist loop), with the cEDH fast mana, dual lands and extra Game-Changer tutors stripped out to stay legal.',
  'Walking Ballista + Mikaeus is NOT a two-card kill on its own - Mikaeus''s +1/+1 keeps a 0-counter Ballista alive, so you need a free sac outlet (you run Viscera Seer, Carrion Feeder and Ashnod''s Altar) to loop the undying. Devoted Druid + Vizier -> Walking Ballista needs no extra piece.',
  'Hold combo pieces until you can protect the turn (Heroic Intervention / Swiftfoot Boots / Sylvan Safekeeper). The commander loop and the go-wide Overrun plan are both there if the Ballista combos get answered.'
)

# --- curated Game Changer menu for this commander (powers the in-page picker -> D.gcOptions) ---
# High-synergy, Bracket-3-legal GCs (the silly cEDH chase ones are excluded). The engine enriches each
# with price / owned / image / synergy; the page lets you swap within the bracket's GC cap.
$gcPicksTxt = @'
Smothering Tithe | Snowballing Treasure ramp that funds Tayam's {3} ability all game; runs in every build.
Survival of the Fittest | Repeatable creature tutor that also bins creatures for Tayam to reanimate - the deck's consistency engine.
Demonic Tutor | Unconditional any-card tutor - the most flexible single consistency slot.
Farewell | Modal exile sweeper: wipe exactly the permanent types you need, around your own board, then rebuild via Tayam.
Crop Rotation | Sacrifices a land to fetch Phyrexian Tower (a free sac outlet) or Bojuka Bog at instant speed.
Aura Shards | In a creature-dense go-wide deck, every creature ETB can blow up an artifact or enchantment - brutal repeatable removal.
Vampiric Tutor | Instant-speed any-card tutor; set up the combo or find an answer on an opponent's end step.
Worldly Tutor | Cheap creature tutor to the top of your library - finds a sac outlet, a payoff, or a Tayam reanimation target.
Enlightened Tutor | Fetches Cathars' Crusade, Smothering Tithe, or Survival of the Fittest to set up the engine.
Orcish Bowmasters | Flash value + pinger that punishes opponents' card draw and leaves an Army - strong black interaction.
Opposition Agent | Flash hatebear that hijacks every opponent's tutor and fetch - powerful disruption.
Drannith Magistrate | Stax hatebear that shuts off opposing commanders and casting from exile or graveyard.
'@
$gcPicks = @(Parse $gcPicksTxt)
"Game Changer picks: $(@($gcPicks).Count)"

# --- flex packages: curated build CHOICES the page surfaces as in-deck swaps (-> D.packages) ---
# Each package is one or more "slots" with mutually-exclusive options of EQUAL size, so swapping stays at 100.
# The option whose cards are in the build is the default; the engine enriches every option (price/owned/etc.).
$packages = @(
  [pscustomobject]@{ name='Finisher'; note='How the fair plan closes a counter-pumped board (1 slot).'; options=@(
    [pscustomobject]@{ label='Overrun'; cards=@([pscustomobject]@{ name='Overrun'; reason='+3/+3 and trample to your whole team for one lethal swing - cheap, and the default in the deck.' }) }
    [pscustomobject]@{ label='Craterhoof Behemoth'; cards=@([pscustomobject]@{ name='Craterhoof Behemoth'; reason='Bigger Overrun: +X/+X and trample where X is your creature count - usually just wins, but {5}{G}{G}{G}.' }) }
    [pscustomobject]@{ label='Triumph of the Hordes'; cards=@([pscustomobject]@{ name='Triumph of the Hordes'; reason='Overrun with infect - only 10 poison to kill, so it ignores big life totals, but it paints a target on you.' }) }
  )}
  [pscustomobject]@{ name='Board wipe'; note='Your reset / catch-up sweeper (1 slot).'; options=@(
    [pscustomobject]@{ label='Austere Command'; cards=@([pscustomobject]@{ name='Austere Command'; reason='Modal: choose two of artifacts / enchantments / small / big creatures - aim it around your own board. Default.' }) }
    [pscustomobject]@{ label='Damnation'; cards=@([pscustomobject]@{ name='Damnation'; reason='Clean {2}{B}{B} destroy-all-creatures with no regeneration - the cheapest, most reliable reset.' }) }
    [pscustomobject]@{ label='Toxic Deluge'; cards=@([pscustomobject]@{ name='Toxic Deluge'; reason='Pay X life for -X/-X to all creatures - kills indestructible and oversized things that dodge destroy effects.' }) }
  )}
  [pscustomobject]@{ name='Protect the combo'; note='Instant-speed protection for the turn you go off (1 slot).'; options=@(
    [pscustomobject]@{ label='Heroic Intervention'; cards=@([pscustomobject]@{ name='Heroic Intervention'; reason='{1}{G}: your permanents gain hexproof + indestructible - beats targeted removal and most wraths. Default.' }) }
    [pscustomobject]@{ label='Flawless Maneuver'; cards=@([pscustomobject]@{ name='Flawless Maneuver'; reason='Free if you control your commander (you do): your creatures gain indestructible - protection for zero mana.' }) }
    [pscustomobject]@{ label="Tamiyo's Safekeeping"; cards=@([pscustomobject]@{ name="Tamiyo's Safekeeping"; reason='{G}: a single permanent gains hexproof + indestructible and you gain 2 life - cheap, targeted protection.' }) }
  )}
)
"Flex packages: $(@($packages).Count)"

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
# curated GC menu -> variants.json gcOptions (name + reason); the engine enriches it into D.gcOptions.
$gcOptions = @($gcPicks | ForEach-Object { [pscustomobject]@{ name=$_.name; reason=$_.reason } })
$out = [pscustomobject]@{ commander=$commander; defaultVariant='owned'; variants=$variants; gcOptions=$gcOptions; packages=$packages }
$out | ConvertTo-Json -Depth 12 | Out-File -Encoding utf8 (Join-Path $outDir 'variants.json')
"Wrote $outDir\variants.json (owned + optimal; $(@($gcOptions).Count) GC options; $(@($packages).Count) flex packages)."
