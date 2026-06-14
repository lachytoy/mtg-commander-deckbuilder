---
name: mtg-setup
description: First-run setup wizard for the MTG Commander Deckbuilder. Use when the user just installed the plugin, has not imported a collection yet, or says "set up my MTG deckbuilder", "get started with the deckbuilder", "import my MTG collection", "how do I start building decks", or similar onboarding phrasing. Walks them through picking a workspace folder, exporting their Moxfield collection, importing it, and building their first commander deck.
---

# MTG Commander Deckbuilder — First-Run Setup

You are guiding a brand-new user through first-time setup. Be friendly and concrete, and do the
mechanical steps for them. Goal: their collection is imported and they have built (or started) their
first Commander deck. Run the PowerShell via the Bash/PowerShell tool.

## 0. Resolve the plugin path (do this at the top of EVERY PowerShell call — shell state does NOT persist between calls)
```powershell
$MTG = $env:CLAUDE_PLUGIN_ROOT            # plugin install dir; engine + templates live here (read-only)
if (-not $MTG) { throw "CLAUDE_PLUGIN_ROOT is not set — is the plugin installed and enabled?" }
```

## 1. Welcome + prerequisites
Briefly tell them what's about to happen (pick a folder → export their Moxfield collection → import it →
build a deck) and confirm prerequisites:
- **Windows** with **PowerShell 5.1+** (ships with Windows 10/11). (Mac/Linux: needs PowerShell 7 / `pwsh`; untested.)
- An internet connection (Scryfall, EDHREC, Commander Spellbook are queried live).
- A **Moxfield** account with their collection entered. No API keys needed.

## 2. Choose a workspace folder
The plugin install is read-only and is replaced on update, so their decks and data must live in a folder
they own. Ask where they'd like to keep their decks (suggest `"$env:USERPROFILE\mtg-decks"`). Then create it
and remember it for future sessions:
```powershell
$ws = "$env:USERPROFILE\mtg-decks"        # <-- substitute the folder they chose
New-Item -ItemType Directory -Force $ws | Out-Null
[Environment]::SetEnvironmentVariable('MTG_WORKSPACE', $ws, 'User')   # persists for FUTURE sessions
$env:MTG_WORKSPACE = $ws                                             # this process
"Workspace set to $ws"
```
**IMPORTANT for the rest of THIS session:** a freshly-set user env var won't reach shells already running,
so pass `-Root "$ws"` explicitly on every engine call below (use the literal path). New sessions pick up
`MTG_WORKSPACE` automatically, and the main **mtg-deckbuilder** skill then needs no `-Root`.

## 3. Export the Moxfield collection
Give them these steps, then ask for the saved CSV's full path:
1. Go to **moxfield.com**, sign in, open your **Collection** (avatar menu → Collection / Binders).
2. Use the collection's **⋯ More** menu → **Export** / **Download CSV**.
3. Save the file and note its path (usually your Downloads folder).

## 4. Import the collection
```powershell
& "$MTG\engine\mtg-engine.ps1" -Stage collection -CollectionCsv "C:\path\to\moxfield_collection.csv" -Root "$ws"
```
This classifies every card via Scryfall (batched ≤70/request) into `data\owned-cards.json` in their workspace.
Report the imported count. If many cards are "not found," the file probably isn't a Moxfield collection export —
have them re-export. (The official Game Changers list auto-fetches on the first build; no action needed.)

## 5. Pick a commander and build the first deck
Ask which commander they want to build around. Then **hand off to the main `mtg-deckbuilder` skill** and run its
full flow — fetch → digest → author the two Bracket-3 builds → build → fact-check the guide against oracle text →
inject — **passing `-Root "$ws"` (literal path) on every `mtg-engine.ps1` call for this first session.** Read
`$MTG\ENGINE.md` for the methodology and the role/bracket templates. Author the card lists and play guide to the
standard described there; never read `data\owned-cards.json` whole — use the `digest` stage's `candidates.md`.

## 6. Done
Point them at the outputs in their workspace and how to continue:
- `"$ws\index.html"` — the home/library page (open in a browser; it lists every deck you build).
- `"$ws\decks\<Commander>.html"` — the interactive deck report (owned/optimal toggle, combos, how-to-play).
- `"$ws\decks\deck-<slug>-owned.txt"` / `-optimal.txt` — Moxfield import files.

Tell them how to keep going:
- Build more: *"build a commander deck for &lt;name&gt;"* (the main **mtg-deckbuilder** skill).
- Update their collection later: *"re-import my MTG collection"* (re-run the `collection` stage with a fresh CSV).

## Notes
- Everything stays local — only public card data is fetched (Scryfall / EDHREC / Commander Spellbook). Prices show in AUD.
- If they ever move their decks folder, update `MTG_WORKSPACE` (re-run the step 2 `SetEnvironmentVariable` line).
