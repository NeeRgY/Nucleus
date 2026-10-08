<div align="center">

# Nucleus

### Modern, highly customizable party and raid frames for World of Warcraft

<img src="https://img.shields.io/github/v/release/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/last-commit/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/issues/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/stars/NeeRgY/Nucleus?style=for-the-badge" />
<br><br>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/neergy)

**Donations and tips support the development and maintenance of Nucleus.**

[![Discord](https://img.shields.io/discord/1538823169446645762?style=for-the-badge&label=Discord&color=5865F2)](https://discord.gg/YjfyDKckCS)

For help, feel free to join the Discord server. I'm usually very active there.

---

**Current version:** `1.0.0`

</div>

<br>

Until today I maintained a fork of Cell. Alongside that I built Nucleus from
scratch, without taking any of Cell's code.
https://github.com/NeeRgY/Cell

## Features

### Frames
- Party and raid frames, plus frames for your pet, group pets and NPC companions
- Spotlight group: pin tanks, healers, a player by name, your target, focus or target's target
- Raid groups: choose which groups and how many are shown, with optional group labels
- Sorting by role, class or raid group, with your own order and pinned names
- Test mode and live previews for every setting

### Indicators
- Name, health text, power bar, level, status, role, leader, ready check, raid marker, combat icon
- Absorb text and shield bar, health thresholds, aggro border, target counter, private auras
- Missing raid buffs, class and specialization icon
- Custom indicators: icons, text, bars, borders, overlays and glows for the auras you choose

### Auras
- Rows for buffs, debuffs, dispellable debuffs, defensive, external and offensive cooldowns, and crowd control
- Built on the game's own aura engine, so auras keep showing in combat on current Retail
- Colored time text, dispel type colors, health bar highlights

### More
- Click-casting per class and per specialization
- Profiles with automatic switching by situation, specialization or role
- Profile export and import as text, backups, and an importer for Cell profiles
- Targeted spell bars, actions (potion and Healthstone animations), ready and pull timer, battle resurrection tracker, marker bar
- Ping mirror on your frames
- English and German

## Supported clients

| Client                 | TOC                    | SavedVariables        | State        |
|------------------------|------------------------|-----------------------|--------------|
| Retail (Midnight 12.1) | `Nucleus_Mainline.toc` | `NucleusDB_Mainline`  | Main version |
| WoW Forever (Classic)  | `Nucleus_Camelot.toc`  | `NucleusDB_Forever`   | Early        |

## Installation

1. Download the latest release.
2. Extract the `Nucleus` folder into your `Interface/AddOns` directory.
3. Start the game, or type `/reload` if it was already running.

The folder must be named `Nucleus`.

## Usage

- `/nucleus` or `/nuc` opens the options window
- `/nuctest` toggles test mode
- `/nucanchor` shows the frame anchors so you can move the frames

## Project layout

Every client has its own isolated file tree under `src/<Client>/`. No Lua file
is shared between clients, so changing one client cannot break another. Only
`Media/` and `Libs/` are shared.

```
src/
  Mainline/   Retail
  Forever/    WoW Forever (Classic)
```

Each tree follows the same module order:

```
Core/           namespace, events, database, defaults, media, util, about, changelog
Locales/        enUS (base) and translations
UI/             skin primitives, widgets, options window
Frames/         secure headers, unit frames, layout, indicators
Integrations/   client-specific hooks (for example ping)
Bootstrap.lua   brings the modules up on login
```

## Support

- Discord: https://discord.gg/YjfyDKckCS
- Issues: https://github.com/NeeRgY/Nucleus/issues
- Ko-fi: https://ko-fi.com/neergy

## License

All rights reserved. You may modify the addon for private use only and may
not redistribute it. See `LICENSE.txt`.
