# MTG Commander Deckbuilder — a Claude Code plugin

Turn your **Magic: The Gathering** collection into tuned **Commander / EDH** decks, with Claude as the
deckbuilding brain. Point it at a commander and it produces **two** complete 100-card decks:

- **Fully owned** — the best deck you can build from your collection *right now* (zero purchases).
- **Optimal** — owned cards plus the upgrades worth buying (excluding silly cEDH chase cards), with AUD prices and buy links.

Each deck is delivered as a **self-contained, interactive HTML report** (deck list grouped by type, an
*Upgrades* tab, a *Stats* tab, detected **combos**, and a written **How-to-play** guide) plus **Moxfield-importable
`.txt`** files. A generated home page lists every deck you build.

Card data and prices come from **[Scryfall](https://scryfall.com)**, recommendations from
**[EDHREC](https://edhrec.com)**, combo detection from **[Commander Spellbook](https://commanderspellbook.com)**,
and bracket / Game-Changer rules from Wizards of the Coast. Decks target **Bracket 3** (≤3 Game Changers, no mass
land denial, late-game combos OK).

> Built and run entirely inside **[Claude Code](https://docs.claude.com/en/docs/claude-code)** — there's no
> server, no account, and no API key. Claude reasons over the card pool and authors the lists; the bundled
> PowerShell engine does the fetching, enrichment, validation, and HTML build.

---

## Requirements

- **Windows 10/11** with **Windows PowerShell 5.1** (preinstalled — nothing to set up). This is the supported,
  tested platform.
- **Claude Code** on **Windows** (see *Compatibility* below — Claude Cowork's sandbox can't run the engine).
- An **internet connection** (Scryfall / EDHREC / Commander Spellbook are queried live during a build).
- A **[Moxfield](https://moxfield.com)** collection you can export to CSV.

> **Mac / Linux:** untested. The engine is PowerShell and would need **[PowerShell 7 (`pwsh`)](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)**
> installed, and likely a few fixes (the scripts use Windows-style `\` paths and were written against Windows
> PowerShell 5.1). If you're on macOS/Linux and want to try, install `pwsh` first — and expect to tinker. PRs welcome.

---

## Compatibility

The engine is **Windows PowerShell** and reads/writes files directly on your machine, so the plugin
only *runs* where Claude Code has local shell + file access:

- ✅ **Claude Code (CLI) on Windows** — fully supported. This is the way to use it.
- ❌ **Claude Cowork** — *not* supported. Cowork executes shell commands in a sandboxed Linux VM (no
  Windows PowerShell), with file access limited to connected folders, so the engine can't run there — even
  though the plugin will appear to "install." Making it Cowork-native would mean rewriting the engine as a
  cross-platform script or a local MCP server; that's a possible future project, not done yet.
- ⚠️ **macOS / Linux** — untested (see the Requirements note above).

## Install

In **Claude Code on Windows**, register this repo and install the plugin — run once, then it stays enabled:
```
/plugin marketplace add lachytoy/mtg-commander-deckbuilder
/plugin install mtg-commander-deckbuilder@lachytoy
```
To pull updates later: `/plugin marketplace update lachytoy`.

**Offline (from a downloaded copy):** download `mtg-commander-deckbuilder-v1.0.0.zip` from the
[latest release](https://github.com/lachytoy/mtg-commander-deckbuilder/releases/latest), unzip it, and start
Claude Code pointed at the folder: `claude --plugin-dir path\to\mtg-commander-deckbuilder`.

## First run — the setup wizard

On your first session after installing, the plugin notices you haven't imported a collection yet and offers to
run the **setup wizard**. You can also trigger it any time by saying:

> **"Set up my MTG deckbuilder"**  *(or run `/mtg-commander-deckbuilder:mtg-setup`)*

The wizard walks you through, conversationally:

1. **Pick a workspace folder** — where your decks and data will live (the plugin install itself is read-only and is
   replaced on update, so your decks go in a folder you own). It remembers this in the `MTG_WORKSPACE` environment
   variable for future sessions.
2. **Export your Moxfield collection** — it gives you the click-by-click steps, then asks for the saved CSV path.
3. **Import it** — classifies every card via Scryfall into your workspace.
4. **Build your first deck** — you name a commander and it runs the full pipeline.

## Everyday use

Once set up, just talk to Claude:

| You say… | What happens |
| --- | --- |
| *"Build a Commander deck for Atraxa, Praetors' Voice"* | Full pipeline → two decks + an HTML report, added to your home page. |
| *"Re-import my MTG collection"* | Re-runs collection import from a fresh Moxfield CSV. |
| *"Rebuild my Ghave deck"* / *"swap X for Y"* | Edits and regenerates that deck. |

Your files all live in your workspace folder:

```
<your workspace>/
  index.html                      ← open this: your deck library / home page
  decks/
    <Commander>.html              self-contained interactive deck report
    deck-<slug>-owned.txt         Moxfield import — Fully owned build
    deck-<slug>-optimal.txt       Moxfield import — Optimal build
  data/                           your classified collection + per-commander build data
```

## How it works

```
commander ─► EDHREC pool ─► [Claude authors 2 Bracket-3 builds] ─► Scryfall enrich + Spellbook combos
          ─► validate (exactly 100, colour-identity legal, no banned, ≤3 Game Changers) ─► self-contained HTML + Moxfield .txt
```

The deckbuilding methodology, data sources, and the (many) PowerShell gotchas are documented in
**[`ENGINE.md`](ENGINE.md)**. The two skills (`mtg-setup`, `mtg-deckbuilder`) drive Claude through it.

## Privacy

Everything runs locally. Your collection file and decks stay in your workspace folder on your machine — nothing is
uploaded anywhere. The only network traffic is public card-data lookups to Scryfall, EDHREC, and Commander Spellbook.
Prices are shown in **AUD** (Scryfall USD × a live FX rate); they're indicative, not live AU retail.

## License & credits

MIT — see [`LICENSE`](LICENSE).

Not affiliated with or endorsed by Wizards of the Coast. *Magic: The Gathering* is © Wizards of the Coast. Card
data, images, and prices courtesy of **Scryfall**; deck recommendations from **EDHREC**; combo data from
**Commander Spellbook**. This is unofficial fan content made for personal use.
