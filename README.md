# PMD Defense (Route Defense)

A Pokémon Mystery Dungeon-style tower defense game. Personal project.

- `unity/` - Unity scripts (C#). The sprites, music and tilesets come from the owner's own ROMs and are **not** in this repo.
- `html/` - the browser version's code.
- `tools/` - the scripts that extract data from the ROMs and build the game.
- `settings/settings.json` - live balance numbers. The Unity app downloads this file on launch,
  so changes here reach the game without rebuilding the app.

## settings.json
| Key | Meaning |
|---|---|
| `waveBase`, `waveStep` | waves at tier 1, extra waves per tier |
| `groupAdd` | tiers added to every fight per map group (Beginner, Intermediate, Advanced, Expert) |
| `groupPay`, `groupCount` | reward and wild-Pokémon-per-wave multipliers per group |
| `groupGate` | tier to clear on any map of the previous group to open each group |
| `threatStep`, `lvPerThreat`, `lvSpread`, `lvSpreadPerThreat` | wild level curve |
| `xpMul`, `xpFullGap`, `xpZeroGap` | XP amount; full XP up to `xpFullGap` levels above the wild Pokémon, none at `xpZeroGap` |
| `upgStep`, `upgMax`, `upgCost` | upgrades of placed Pokémon: bonus per level, levels, cost per level (share of placing cost) |
| `rarity` | spawn weight for Common, Uncommon, Rare, Very rare |
| `weatherWaves` | how many waves bought weather lasts |
| `startCash`, `startCashPerThreat`, `winPay`, `winPayPerThreat` | battle cash at the start, ₽ for a win |

Raise `version` with every change.
