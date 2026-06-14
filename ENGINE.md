# MTG Commander Deckbuilder — Engine Runbook

This is the canonical, repeatable process for building a commander deck from a collection.
It pairs **mechanical scripts** (data fetching, enrichment, validation, HTML build) with an
**AI reasoning step** (card selection), which is the part a human/Claude does. Read this top to
bottom before building a new commander.

Inputs: a commander name · a Moxfield collection CSV. Target is **Bracket 3** (≤3 Game Changers,
no mass land denial, late-game combos OK).
Outputs: `deck-data.json`, a Moxfield-importable `.txt` per build, and a self-contained
`<Commander>.html` report with a **Fully owned / Optimal** toggle (no bracket toggle).

**Deck model (current):** exactly TWO Bracket-3 decks per commander —
- **`owned` (Fully owned):** the best deck from the collection right now (0 buys).
- **`optimal` (Optimal):** the best Bracket-3 deck overall = owned cards + the buys worth making,
  excluding the silly cEDH chase cards (the `$chase` denylist); no per-card price cap otherwise.

Both lists are **hand-authored** (the AI step) in `engine/handbuild.ps1`, not auto-generated.
The old per-bracket model (B1–B5 × owned/recommended + cEDH) and `engine/autobuild.ps1` are
retired — kept only as a generic fallback generator for brand-new commanders.

**Token discipline (important):** the collection lives in DATA (`owned.json`/`owned-cards.json`),
classified once and reused for every commander — it is NOT in any script. When authoring a deck,
read the compact `data/<slug>/candidates.md` from the `digest` stage (~10–35 KB), and `Grep`
`owned-cards.json` for specific theme cards. **Never read the 1.7 MB `owned-cards.json` whole** —
that is what makes a build expensive.

---

## Pipeline at a glance

```
                                     ┌─ (once) classify full collection ─┐
collection.csv ──► owned.json ──────►│  Scryfall /cards/collection       │──► owned-cards.json   (SHARED, reused for every commander)
                                     └───────────────────────────────────┘
                              (once) Scryfall is:gamechanger ──► game-changers.json (SHARED, refresh ~quarterly)

per commander:
  commander ──► EDHREC slug ──► json.edhrec.com page ──► build-sheet.json  (candidate pool: inclusion% + synergy)
  [AI step] hand-author variants.json — two Bracket-3 builds (owned + optimal) with per-card reasons (handbuild.ps1)
  enrich ──► Scryfall for any non-owned cards + Commander Spellbook combos + merge owned-legal pool
            ──► deck-data.json (small: commander+variants+fx) + pool-data.json (big: the legal pool)   [VALIDATED before write]
  inject deck-data.json + pool-data.json into deckbuilder-template.html ──► <Commander>.html + deck-<slug>-<build>.txt
```
**Data split (since 2026-05):** `build` writes the deck (`deck-data.json`) separately from the candidate
pool (`pool-data.json`). `inject` inlines the deck into `window.DECK_DATA` and the pool into a separate
inert `<script type="application/json" id="pooldata">` block that the page **parses lazily** on first
Add-cards-drawer open (so the deck renders instantly). Still one self-contained file that works over
`file://` — a hosted backend can instead serve `pool-data.json` from a URL without a template rewrite.
**Validation is hard:** `build` validates BEFORE writing and `throw`s (writing nothing) on count≠100,
off-identity, banned, or Game-Changers-over-cap — an illegal deck never produces output.

## Data sources (see also memory `mtg-data-sources`)
- **Scryfall** `api.scryfall.com` — card data/prices/legality/images. No key, CORS-ok. Truth source.
- **EDHREC** `json.edhrec.com/pages/commanders/<slug>.json` — community card pool by category with
  `num_decks`/`potential_decks` (→ inclusion %) and `synergy`. NOT CORS-enabled (fetch server-side).
- **Commander Spellbook** `backend.commanderspellbook.com/find-my-combos` (POST) — detects combos
  in the 99. We capture the RICH fields per combo: card images + `zoneLocations` + card states,
  generic `requires` templates (e.g. "a Persist creature"), numbered `description` steps,
  `manaNeeded`, `produces`, `popularity`, and the combo `id` (→ `commanderspellbook.com/combo/<id>/`).
  GOTCHA: `results.included` lists a combo once its named `uses` cards are present **even if a
  `requires` template piece is still missing**. So split combos by `requires.length`: 0 = "ready",
  >0 = "one piece away" (the HTML does this; don't report the raw included count as all-live).
- **Game Changers** — `api.scryfall.com/cards/search?q=is:gamechanger` (self-updating official list).

## Hard gotchas (these cost real debugging time — don't relearn them)
1. **Scryfall `/cards/collection` caps at 75 identifiers per POST.** Batch in ≤70.
2. **PowerShell 5.1 mangles non-ASCII POST bodies** (e.g. "Bartolomé" → 400). Always send
   `[Text.Encoding]::UTF8.GetBytes($body)` with `-ContentType 'application/json; charset=utf-8'`.
3. **Read JSON with `Get-Content -Raw -Encoding UTF8`** or accented names mojibake.
4. **PowerShell 5.1 `if` is a statement, not an inline expression.** `(if(x){a}else{b})` and
   bare `if(cond)return;` both fail. Use `$(if(x){a}else{b})`, or precompute into a variable, and
   always brace: `if(cond){return}`.
5. **`$var:` in a double-quoted string** is parsed as a drive ref. Use `$($var):`.
6. **`Out-File -Encoding utf8` writes a BOM** in PS5.1 — fine for our reads, but be aware.
7. **`ConvertFrom-Json` emits a parsed JSON array as a SINGLE pipeline item.** So `@(Read-Json $p).Count`
   returns 1 (not the element count), and `@(Read-Json $p)` wraps the whole array as one element. Always
   **assign first, then wrap**: `$x = Read-Json $p; @($x)`. (`foreach($e in (Read-Json $p))` is fine — it
   enumerates.) This silently breaks counts and any multi-element manifest if you forget.
8. **`ConvertTo-Json -Compress` unwraps a 1-element array into a bare object** in PS5.1. When a file must be a
   JSON array regardless of length (e.g. `pool-data.json`), emit `[]`/`[{...}]` explicitly for the 0/1 cases.

---

## The deckbuilding methodology (the AI step)

For each commander you produce **two Bracket-3 builds** (`owned` + `optimal`). Card **selection** is
judgement (Claude), grounded in EDHREC inclusion/synergy + the role taxonomy + the owned set + the
detected combos. Status (owned/buy), type, role, legality, price, combos are all computed by the
scripts — you choose the names and write a one-line `reason` per card in `engine/handbuild.ps1`.

### Role taxonomy (auto-classified from oracle/type; signals)
- **ramp** — mana rocks/dorks, land-fetch, "add {…}", treasure, extra-land.
- **card-draw** — "draw … cards", repeatable draw engines, investigate, impulse.
- **spot-removal** — "destroy/exile target", -X/-X, edicts, fight.
- **board-wipe** — "destroy/exile all", mass -X/-X, "deals N to each creature".
- **protection** — hexproof/indestructible/ward grant, phase out, defensive counters, prevent.
- **recursion** — graveyard→hand/battlefield, flashback/escape.
- **tutor** — non-land library search to hand/battlefield (bracket-relevant for heavy-tutor checks).
- **finisher** — "you win", mass drain, overrun, infinite-combo payoff.
- **land** / **synergy** (residual, theme payoffs).
- Multi-role precedence when fitting a template: land > ramp > tutor > board-wipe > spot-removal >
  recursion > finisher > card-draw > protection > synergy.

### Bracket-3 composition template (99 non-commander cards; a starting point, flex ±2 by curve)
~36 lands · ~10 ramp · ~10 draw · ~7 spot removal · ~3 wipes · ~3 protection · ~30 synergy/flex.
Power constraints: **≤3 Game Changers**, late-game 2-card combos OK, **no mass land denial** or
extra-turn loops. The Optimal build can run a slightly leaner manabase (35) thanks to more low-curve
ramp + tutors.

### The two builds (variant keys = `owned`, `optimal`)
- **`owned` (Fully owned):** only cards in the collection (0 buys). The best honest deck right now.
- **`optimal` (Optimal):** owned-first, plus the best *buys EXCLUDING the "silly cEDH" chase cards*
  (ABUR duals, expensive Moxen, Gaea's Cradle, Ancient Tomb, Mana Vault, Imperial Seal, etc. — the
  `$chase` denylist). **No per-card price cap**, just the chase exclusion. The HTML marks each card
  owned/buy, shows AUD prices, and keeps the mtgmate buy links on the Upgrades tab.

Author both in `engine/handbuild.ps1` (pipe-delimited `Name | reason | count?` lists per build +
the play metadata), then run `build` to enrich + detect combos + validate. The GC budget is spent
deliberately: pick which ≤3 Game Changers each build runs (owned copies of others are simply left
out to stay under the cap). Use the detected combos to confirm — and to discover lines you didn't
plan (e.g. Basking Broodscale + Cathars' Crusade showed up in the owned build).

### Play metadata you author per build (`theme`, `howToPlay`, `wincons`, `comboNotes`)
This is the pilot's guide and it is rendered in the HTML — write it as carefully as the card list.
- **`howToPlay.win`** — **REQUIRED, the most important field.** A plain-language "how you actually win
  this game" paragraph (2–5 sentences). It renders FIRST on the *How to play* tab in the **"How you win
  this game"** panel, above the keep/early/mid/late/style sections. Lead with the most reliable line.
  **For a combo, always name the payoff that converts the loop into a win** ("infinite death triggers do
  nothing without Blood Artist / Bastion of Remembrance in play — that is what drains the table"). **Always
  state the FAIR plan** for when no combo assembles (go-wide + Overrun, aristocrat drip, evasive beats,
  draw-out). Never hand-wave with "out-value the table" — say exactly how damage/decking happens.
- **`howToPlay.keep` / `.early` / `.mid` / `.late` / `.style`** — concrete, turn-numbered piloting advice
  that names real cards from *this* build. `late` should read like a step-by-step kill sequence.
- **`wincons`** — 2–4 bullets, each a concrete win path naming the real cards AND the closing payoff. These
  render under "How you win this game" (and on the Stats tab's "Game plan").
- **`comboNotes`** — bracket-compliance / combo-discipline notes (the ⚑ lines on the Stats tab).
- **Accuracy bar:** every card named must be in that build, and every rules claim must be correct (e.g.
  card X "draws 3", a flip trigger, what a loop actually produces). Treat this like an adversarial fact-check.

#### Fact-check the guide against Scryfall oracle text — NOT from memory
The play metadata is the most error-prone thing you write: it is easy to assert a card does something it
doesn't (shroud vs hexproof, "each opponent" vs "target player", a +X/+X that doesn't exist, a loop that
makes ETB triggers but not deaths, a tutor that checks toughness not power). **Do not trust your own
recollection of a card.** After `build`, every card carries its real `oracle_text` (pulled from Scryfall)
in `data/<slug>/deck-data.json` — that is the source of truth. Before you ship, verify every rules claim
in `howToPlay` + `wincons` against that text. Concrete recipe:
1. **Read `data/<slug>/oracle.md`** — `build` writes it automatically: one line per unique card across the
   commander + both builds (`Name [type_line] :: oracle`), ~10–20 KB. This is the ground truth to check
   against — **read THIS, not the ~175 KB `deck-data.json` and never the 1.7 MB `owned-cards.json`.** (If you
   ever need a build-scoped slice, the same text is at `.commander.oracle_text` / `.variants.<build>.cards[].oracle_text`.)
2. Cross-check each claim against that text: does the named card actually do what the guide says, with the
   right numbers, targets, token types, and trigger conditions? Does every combo step the oracle supports,
   and does each loop name a payoff actually in the build that converts it to a win?
3. Fix every mismatch in the handbuild script, re-run `handbuild` → `build`, and re-check.
This catches the classes of bug above that a from-memory pass misses. For a thorough sweep, fan out one
checker per build (parallel subagents or a workflow), each given ONLY that build's oracle dump + guide and
told to use nothing but the provided text — memory is what introduces the errors in the first place.

### Interactive combo suggestions (capability tags → "one piece away" → add it live)
Commander Spellbook combos come back with `requires` template pieces (e.g. "Persist Creature", "Free
sacrifice outlet", "Mana dork", "Permanent that can be cast using {C}"). The HTML turns these into
*actionable* decisions: each near-combo lists the owned/buyable cards from your pool that satisfy the
missing piece, and clicking one adds it and re-evaluates combos **live** (near → ready), so you can explore
"what unlocks if I add X?" entirely in the app. Two moving parts:
- **`Get-Tags` (engine)** bakes lightweight *capability tags* onto every deck + pool card from its oracle
  text — `persist`, `freesac` (a FREE repeatable sac outlet; excludes tap-gated lands), `manadork`,
  `hastegiver`, `untapper`, `tokendoubler`, `counterdoubler`, `flicker` (plus the functional tags draw/
  ramp/removal/drain/etc.). No oracle text is stored on pool rows — just the tags.
- **`TEMPLATEMATCH` (deckbuilder-template.html)** maps a Spellbook template *name* → a predicate over a card
  (usually a tag check; a few read fields, e.g. colorless-castable from `mana_cost`). `comboReady` is now
  dynamic: a combo is ready when every `requires` template is satisfied by a card in the live (edited) deck.
To support a NEW template, prefer adding a precise tag in `Get-Tags` + one row in `TEMPLATEMATCH`. Keep
detection high-precision: an unmatched template degrades to a non-actionable hint (correct), whereas a loose
matcher suggests cards that don't actually combo (wrong). The app can only act on combos the pipeline already
discovered — finding net-new combos from an arbitrary card still requires a `build` re-run.

### Prose rendering on the non-deck tabs (you author plain text; the template does the rest)
You write `howToPlay`/`wincons`/`comboNotes`/`theme` as plain prose — the template makes it readable:
- **Card hover-links** — any card NAME mentioned (built once into `CARDIMG` from the commander + every
  build's cards) is wrapped in a `.cardlink` that shows the card image on hover/focus, via the same
  `floatimg` mechanism as the deck rows. The commander art (`.cmd`) is hoverable too. Matching is
  case-sensitive proper-noun, longest-first, and skips basics, so verbs like "consider" aren't linked.
- **Auto-formatting** (`fmtGuide`) turns a prose slab into bullets, splitting on sentences and on
  enumerations/step markers (`(1)`, `TURN 1:`, `PATH A`, `STEP 1`), and bolds leading labels
  (`MULLIGAN:`, `CRITICAL:`, etc.). The How-to-play sections stack full-width (`.gsecs`) to avoid the
  ragged blank space a 2-column grid leaves. So author with natural markers (number your steps, prefix
  `TURN n:` / `MULLIGAN:`) and it formats cleanly — no HTML in the metadata.
- **Combo pieces** show the actual deck card filling a satisfied template (a `requires` "Persist Creature"
  renders as "Kitchen Finks"), excluding cards already named in that combo so one card never fills two roles.

### Validation gates (`build` enforces these BEFORE writing — a failing build `throw`s and writes nothing)
- Exactly **100 cards** (1 commander + 99).
- Every card's `color_identity` ⊆ commander identity.
- No `legalities.commander === "banned"` cards.
- Game Changers count ≤ 3 (bracket cap).
- (Advisory) sources-per-pip vs curve; combos detected + their bracket tags.

---

## Running it for a NEW commander

```powershell
# 0. (once, or when the collection changes) classify the whole collection — SHARED across commanders. REQUIRED first.
.\engine\mtg-engine.ps1 -Stage collection -CollectionCsv "<path>\moxfield_haves.csv"
#    To RE-classify after an engine change (no CSV needed), omit -CollectionCsv — it re-runs from data/owned.json:
.\engine\mtg-engine.ps1 -Stage collection
#    (The official Game Changers list is auto-fetched on first build; re-run this to refresh it occasionally.)
.\engine\mtg-engine.ps1 -Stage gamechangers

# 1. fetch the commander's EDHREC candidate pool -> data/<slug>/build-sheet.json + candidates-cards.json.
.\engine\mtg-engine.ps1 -Stage fetch -Commander "Atraxa, Praetors' Voice"

# 1b. digest: write a COMPACT, role-bucketed candidates.md (~10-35 KB). READ THIS to pick cards -
#     never dump the 1.7 MB owned-cards.json into context. (collection = data, classified once, reused.)
.\engine\mtg-engine.ps1 -Stage digest -Commander "Atraxa, Praetors' Voice"

# 2. [AI STEP] hand-author the two Bracket-3 builds (owned + optimal) with per-card reasons.
#    Copy engine/handbuild.ps1 to engine/handbuild-<slug>.ps1, swap in $commander + the two card
#    lists + play metadata. The write path is auto-derived from $commander -> data/<slug>/variants.json
#    (no path edit needed). (autobuild.ps1 is a generic fallback only.)
.\engine\handbuild-<slug>.ps1     # writes data/<slug>/variants.json with the owned + optimal builds

# 3. enrich + Spellbook combos + pool + validate (read the combos it finds — may reveal new lines!)
.\engine\mtg-engine.ps1 -Stage build -Commander "Atraxa, Praetors' Voice"
#    -> data/<slug>/deck-data.json (variants map + pool + fxAud) + validation per build

# 4. build the shareable HTML + a Moxfield .txt per build
.\engine\mtg-engine.ps1 -Stage inject -Commander "Atraxa, Praetors' Voice"
#    -> <Commander>.html  and  deck-<slug>-owned.txt / deck-<slug>-optimal.txt

# 5. verify in the browser (preview_start "mtg" -> open /decks/<Commander>.html), iterate.
```
Prices are shown in **AUD**: Scryfall `prices.usd` x a live USD->AUD rate (`data/fx.json`, auto-fetched
from open.er-api.com). mtgmate.com.au is bot-protected (403), so real AU retail isn't pullable at
scale — buy cards deep-link to mtgmate search instead. Buy lists exclude the `$chase` cards.

EDHREC slug = lowercase, strip diacritics + apostrophes/commas/periods, non-alphanumerics → `-`,
collapse/trim dashes (e.g. "Atraxa, Praetors' Voice" → `atraxa-praetors-voice`). Partner pairs use a
combined slug; double-faced commanders use the front face — verify the URL resolves before relying on it.

## Front door (the local "website")
`index.html` is the home/library page — the front door for starting builds and browsing finished decks.
It is regenerated by the engine (`-Stage home`, and automatically at the end of `inject`) from
`engine/index-template.html` + the `data/decks.json` manifest, with the deck tiles baked in (pure static HTML,
so it works on `file://` — no server). It is the **only `.html` in the project root**; built deck pages live in
`decks/` and the home tiles link to them. **New decks are created by the `mtg-deckbuilder` skill** (a PERSONAL
skill, see below): open a Claude Code session and say "build a new commander deck for <name>". The skill runs the
whole pipeline and the per-deck HTML is the deck view. (This keeps Claude as the deckbuilding brain — no backend.)

## File layout
```
mtg-deckbuilder/
  index.html                     GENERATED front door / deck library — the ONE file you open
  README.md                      quick how-to (points at index.html)
  ENGINE.md                      this runbook
  REVIEW.md                      code-review / fix history
  decks/                         every built deck:
    <Commander>.html               self-contained deck report (opened from index.html tiles)
    deck-<slug>-<build>.txt        Moxfield imports (owned / optimal / default)
  engine/                        the machinery (not opened directly):
    mtg-engine.ps1                 the pipeline (collection|gamechangers|fetch|digest|build|inject|home)
    handbuild.ps1                  the AI step + copy-me template; auto-writes data/<slug>/variants.json from $commander
    deckbuilder-template.html      SHARED deck UI shell (__DECK_DATA_PLACEHOLDER__ + __POOL_DATA_PLACEHOLDER__ +
                                   __MANA_SPRITE__; also holds the CHASE denylist the in-page replace-picker excludes)
    index-template.html           SHARED home-page shell (__DECKS_HTML__ + __COLLECTION_HTML__ + __MANA_SPRITE__)
    mana-sprite.svg                inline WUBRGC mana-symbol sprite (official Scryfall glyphs); inlined into both
                                   templates at the __MANA_SPRITE__ placeholder so pips/mana costs work offline
    autobuild.ps1                  RETIRED generic fallback (still the home of the original `$chase` denylist)
  data/
    owned.json, owned-cards.json SHARED — the classified collection (reused for every commander)
    game-changers.json           SHARED — official list
    decks.json                   SHARED — the deck-library manifest (one entry per built deck)
    <slug>/                      per-commander: edhrec*.json, build-sheet.json, candidates-cards.json,
                                 candidates.md (compact digest), variants.json, deck-data.json, pool-data.json,
                                 oracle.md (compact per-card oracle dump for the fact-check step)
```
**Workspace vs code (so this can ship as an installed plugin):** the engine + HTML templates always load from
the `engine/` folder (`$PSScriptRoot`), wherever installed. The user's data/decks/index.html — the "workspace" —
resolve via `-Root` > `$env:MTG_WORKSPACE` > the engine's parent folder. In the in-repo layout (no override) the
workspace IS `mtg-deckbuilder/`, exactly as shown above; installed as a plugin, point `MTG_WORKSPACE` at any folder
and the engine writes there while reading code from the install. **Every commander lives in `data/<slug>/`** (no
special cases); deck HTML always writes to `<workspace>/decks/`.

## Known limitations / next improvements (from the review)
- Combo bracket-classification is read from Spellbook's `bracketTag`; we surface a density warning
  but don't auto-trim. Low-bracket combo *timing* is still partly judgement.
- Role classification is regex heuristics; upgrading to Scryfall Tagger `otag`/function tags would
  improve accuracy and enable a curve-adaptive template.
- The HTML embeds the full legal pool (~1.4k cards → ~2 MB file). Fine locally; for the hosted site,
  serve the pool from a backend instead of inlining.
- Manabase is chosen by judgement + a pip check; a true sources-per-pip solver is a future gate.
