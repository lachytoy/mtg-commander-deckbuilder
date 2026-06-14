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
- **Claude Code** (the CLI/desktop app you're reading this in).
- An **internet connection** (Scryfall / EDHREC / Commander Spellbook are queried live during a build).
- A **[Moxfield](https://moxfield.com)** collection you can export to CSV.

> **Mac / Linux:** untested. The engine is PowerShell and would need **[PowerShell 7 (`pwsh`)](https://learn.microsoft.com/powershell/scripting/install/installing-powershell)**
> installed, and likely a few fixes (the scripts use Windows-style `\` paths and were written against Windows
> PowerShell 5.1). If you're on macOS/Linux and want to try, install `pwsh` first — and expect to tinker. PRs welcome.

---

## Install

In Claude Code, add this repo as a plugin marketplace and install the plugin:

```
/plugin marketplace add lachytoy/mtg-commander-deckbuilder
/plugin install mtg-commander-deckbuilder@lachytoy
```

(Equivalent CLI form: `claude plugin marketplace add lachytoy/mtg-commander-deckbuilder` then
`claude plugin install mtg-commander-deckbuilder@lachytoy`.)

That's it — the plugin bundles everything it needs (engine, templates, the mana-symbol assets, and the skills).

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
