---
name: mtg-deckbuilder
description: Build a Commander/EDH deck from your MTG collection. Use when asked to "build a new commander deck", "build a deck for <commander>", make/generate an EDH/Commander deck, re-import the MTG collection, or edit/rebuild an existing deck. Runs the PowerShell engine (EDHREC pool -> two hand-authored Bracket-3 builds -> Scryfall enrich + Commander Spellbook combos -> validate -> self-contained HTML) and updates the home/library page.
---

# MTG Commander Deckbuilder

You are the deckbuilding brain. This skill runs the full pipeline and authors two Bracket-3 decks
(`owned` = best from the collection now, `optimal` = owned + worthwhile buys) to a consistent standard.
The mechanical work is PowerShell; the **card selection + reasons + play guide is you**.

**First run?** If no collection has been imported yet, run the **mtg-setup** wizard first (the user can say
*"set up my MTG deckbuilder"*) — it picks a workspace folder, imports a Moxfield collection, and builds the
first deck. This skill assumes the collection is already imported.

**Engine location & workspace — resolve both at the top of EVERY PowerShell call (shell state does NOT persist
between calls).** `$MTG` = where the engine code lives (scripts at `$MTG\engine\`); `$WS` = where the user's
data/decks/index.html live. The scripts derive their own code root, so you can invoke them by absolute path
from any working directory.

```powershell
$MTG = if($env:CLAUDE_PLUGIN_ROOT){ $env:CLAUDE_PLUGIN_ROOT } else { throw "CLAUDE_PLUGIN_ROOT not set — install this as a plugin, or set it to the plugin folder." }
$WS  = if($env:MTG_WORKSPACE){ $env:MTG_WORKSPACE } else { $MTG }   # data/, decks/, index.html live here
```
Installed as a plugin, the **mtg-setup** wizard sets `$env:MTG_WORKSPACE` to a folder the user chose, so their
decks never land inside the read-only install. The engine reads `MTG_WORKSPACE` itself, so once it is set (new
sessions inherit it) no `-Root` is needed; in the very first session right after setup, pass `-Root "<workspace>"`
explicitly because a just-set env var won't reach shells already running.

**Deep reference:** read `$MTG\ENGINE.md` for the full methodology, data sources, and gotchas. This skill is the
action checklist; ENGINE.md is the manual. Keep changes minimal and **never read the 1.7 MB `data/owned-cards.json` whole**.

## A. Build a NEW commander deck (the main flow)
Slug = lowercase, strip diacritics/punctuation, non-alphanumerics -> `-` (e.g. "Atraxa, Praetors' Voice" -> `atraxa-praetors-voice`).

1. **Fetch** the EDHREC candidate pool (-> `data/<slug>/build-sheet.json` + `candidates-cards.json`):
   ```powershell
   & "$MTG\engine\mtg-engine.ps1" -Stage fetch -Commander "Atraxa, Praetors' Voice"
   ```
2. **Digest** -> compact role-bucketed shortlist (~10-35 KB). READ THIS, not owned-cards.json:
   ```powershell
   & "$MTG\engine\mtg-engine.ps1" -Stage digest -Commander "Atraxa, Praetors' Voice"
   ```
   Then read `$WS\data\<slug>\candidates.md`. `Grep` `$WS\data\owned-cards.json` for specific theme cards if needed.
3. **Author the two builds** (the AI step). Copy `engine\handbuild.ps1` to `engine\handbuild-<slug>.ps1` and edit:
   - set `$commander`,
   - replace both card lists (`$ownedNonland`/`$ownedLands`, `$optNonland`/`$optLands`) — pipe-delimited
     `Name | one-line reason | count?` (basics carry a count),
   - replace the play metadata (`$theme*`, `$how*`, `$wincons*`, `$combo*`). **`howToPlay.win` is
     REQUIRED and is the headline of the guide**: a clear, well-written "how you actually win this game"
     paragraph that renders first on the How-to-play tab. Name the payoff that turns any combo into a win
     and always give the fair non-combo plan; keep `late`/`wincons` concrete. See ENGINE.md "Play metadata".
   (the write path is auto-derived from `$commander` -> `data\<slug>\variants.json`; no path edit needed).
   Follow the **Bracket-3 composition** + **role taxonomy** in ENGINE.md: ~36 lands / ~10 ramp / ~10 draw /
   ~7 spot removal / ~3 wipes / ~3 protection / ~30 synergy; **<=3 Game Changers** (pick which 3 deliberately);
   no mass land denial / no extra-turn loops; `optimal` excludes the silly cEDH chase cards (ABUR duals,
   expensive Moxen, Gaea's Cradle, Ancient Tomb, Mana Vault, Imperial Seal, etc.) — no price cap otherwise. Run it:
   ```powershell
   & "$MTG\engine\handbuild-<slug>.ps1"
   ```
4. **Build** (enrich + Spellbook combos + owned-legal pool + VALIDATE; read the combos it finds — they can reveal
   unplanned lines worth keeping). Build **throws and writes nothing** if a deck isn't exactly 100, is off-identity,
   has a banned card, or exceeds the Game-Changer cap — fix the list and re-run:
   ```powershell
   & "$MTG\engine\mtg-engine.ps1" -Stage build -Commander "Atraxa, Praetors' Voice"
   ```
   **Then fact-check the `howToPlay`/`wincons` text against the real Scryfall oracle text — NOT from memory**
   (shroud≠hexproof, "each opponent"≠"target player", phantom +X/+X, ETB vs death triggers, toughness vs power).
   `build` writes **`data\<slug>\oracle.md`** (one compact line per card) for exactly this — **read THAT, not the
   ~175 KB `deck-data.json`**. See ENGINE.md "Fact-check the guide against Scryfall oracle text". Fix mismatches
   in the handbuild script and re-run `handbuild`→`build`.
5. **Inject** -> self-contained `decks\<Commander>.html` + Moxfield `.txt` per build (all into `decks\`);
   auto-updates the front-door `index.html` + `data\decks.json`:
   ```powershell
   & "$MTG\engine\mtg-engine.ps1" -Stage inject -Commander "Atraxa, Praetors' Voice"
   ```
6. **Verify** (once): `preview_start "mtg"`, open `/decks/<Commander>.html` (root-relative — doc root is the workspace folder).
   Check: no console errors; both decks exactly **100**; **<=3 Game Changers**; every card within the commander's
   colour identity; 0 banned; combos/upgrades/edit-swap work. Also open `/index.html` (the front door) and confirm the new deck tile.
   File layout: `index.html` is the only HTML in the workspace root; built deck pages + Moxfield `.txt`s live in `decks\`; the UI templates live in `$MTG\engine\`.

## B. Re-import the collection (after you edit it)
Fresh Moxfield CSV supplied:
```powershell
& "$MTG\engine\mtg-engine.ps1" -Stage collection -CollectionCsv "C:\path\to\moxfield_haves.csv"
& "$MTG\engine\mtg-engine.ps1" -Stage home
```
Engine/classification changed but no new CSV — re-classify from the existing `data\owned.json`:
```powershell
& "$MTG\engine\mtg-engine.ps1" -Stage collection      # no -CollectionCsv = re-classify in place
& "$MTG\engine\mtg-engine.ps1" -Stage home            # refresh the collection count on index.html
```
Refresh the official Game Changers list occasionally: `& "$MTG\engine\mtg-engine.ps1" -Stage gamechangers`.

## C. Edit / rebuild an existing deck
Edit that commander's `engine\handbuild-<slug>.ps1` (or `data\<slug>\variants.json`), then re-run `handbuild` -> `build` -> `inject`.

## Critical gotchas (don't relearn these)
- **Every commander lives in `data\<slug>\`** — no special cases. The collection must be imported first (section B);
  `build`/`digest` error clearly if it isn't, and the Game Changers list auto-fetches on first run.
- PowerShell 5.1: `ConvertFrom-Json` returns a parsed array as a SINGLE item — `@(Read-Json $p).Count` lies (returns 1);
  assign to a variable first, then `@($x)`. Read JSON with `-Encoding UTF8`. Scryfall `/cards/collection` caps at 75 ids/POST.
- DFC/split names ("Front // Back") are sent front-face-only to Scryfall (engine handles it). Network calls auto-retry 429/5xx.

## What NOT to do
- Don't read `data\owned-cards.json` or any generated `*.html` / `deck-data.json` / `pool-data.json` whole — work
  from `candidates.md`, the `.ps1` scripts, and targeted `Grep`.
- Don't add `oracle_text` to pool rows or re-bloat the pool. Don't ship a build that fails validation. Don't exceed
  3 Game Changers. Desktop-only — skip mobile/responsive work.
