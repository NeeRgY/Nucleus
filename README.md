<div align="center">

# Nucleus

### Modern, highly customizable party and raid frames for World of Warcraft

<img src="https://img.shields.io/github/v/release/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/last-commit/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/issues/NeeRgY/Nucleus?style=for-the-badge" />
<img src="https://img.shields.io/github/stars/NeeRgY/Nucleus?style=for-the-badge" />
<a href="https://www.curseforge.com/wow/addons/nucleus"><img src="https://img.shields.io/curseforge/dt/1723779?style=for-the-badge&logo=curseforge&label=CurseForge&color=F16436" /></a>
<br><br>

[![ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/neergy)

**Donations and tips support the development and maintenance of Nucleus.**

[![Discord](https://img.shields.io/discord/1558448385084891220?style=for-the-badge&label=Discord&color=5865F2)](https://discord.gg/HTgSf7Bjy8)

For help, feel free to join the Discord server.

---

**Current version:** `1.1.2`

</div>

<br>

Until today I maintained a fork of Cell. Alongside that I built Nucleus from
scratch, without taking any of Cell's code.
https://github.com/NeeRgY/Cell

## Features

### Frames
- Party and raid frames, plus frames for your pet, group pets and NPC companions
- Party target frames: the target of each party member, optionally only for tanks, healers or damage dealers
- Spotlight group: pin tanks, healers, a player by name, your target, focus or target's target
- Raid groups: choose which groups and how many are shown, with optional group labels
- Sorting by role, class or raid group, with your own order and pinned names
- Test mode and live previews for every setting

### Indicators
- Name, health text, power bar, level, status, role, leader, ready check, raid marker, combat icon
- Power bar colors by resource or by role, with a custom color per bar
- Absorb text and shield bar, health thresholds, aggro border, target counter, private auras
- Overheal display for the heal prediction (WoW Forever)
- Cast bar: the spell a group member is casting, with icon, name, target and time, interrupt flash, colors per cast type and your choice of position
- Missing raid buffs, class and specialization icon
- Custom indicators: icons, text, bars, borders, overlays and glows for the auras you choose

### Auras
- Rows for buffs, debuffs, dispellable debuffs, defensive, external and offensive cooldowns, and crowd control
- Built on the game's own aura engine, so auras keep showing in combat on current Retail
- Aura sounds: a sound when an aura appears, disappears or gains a stack, with included sounds and your own files
- Colored time text, dispel type colors, health bar highlights

### More
- Click-casting per class and per specialization, with a smart resurrection that picks the normal or the combat spell
- Profiles with automatic switching by situation, specialization or role
- Profile export and import as text, backups, and an importer for Cell profiles
- Targeted spell bars, actions (potion and Healthstone animations), ready and pull timer, battle resurrection tracker, marker bar
- Ping mirror on your frames
- Font outline styles including Shadow, fonts and bar textures from LibSharedMedia, 11 languages

## Supported clients

| Client                 | Game version           | TOC                    | SavedVariables        | State        |
|------------------------|------------------------|------------------------|-----------------------|--------------|
| Retail                 | 12.1, 12.1.5, 12.1.7   | `Nucleus_Mainline.toc` | `NucleusDB_Mainline`  | Early        |
| WoW Forever (Classic)  | 1.60.1                 | `Nucleus_Camelot.toc`  | `NucleusDB_Forever`   | Early        |
| Vanilla                | 1.15.8, 1.15.9         | `Nucleus_Vanilla.toc`  | `NucleusDB_Vanilla`   | Early        |
| TBC                    | 2.5.6                  | `Nucleus_TBC.toc`      | `NucleusDB_TBC`       | Early        |

Aura sounds and the cast bar are available on Retail and WoW Forever.

## Installation

1. Download the latest release.
2. Extract the `Nucleus` folder into your `Interface/AddOns` directory.
3. Start the game, or type `/reload` if it was already running.

The folder must be named `Nucleus`.

## Usage

Open the options with `/nuc` or a click on the minimap button. Press Ctrl+F in the options window to search every setting.

| Command | What it does |
|---------|--------------|
| `/nucleus` or `/nuc` | Opens or closes the options window |
| `/nuctest` | Toggles test mode |
| `/nucanchor` | Shows the frame anchors so you can move the frames |
| `/nucnews` | Opens the "What's new" window |

For bug reports there are a few more: `/nucdebug`, `/nucauras [unit]`, `/nucorder`, `/nucsize`, `/nucnpc`, `/nucblizz`, `/nuctaint` and `/nuctaintlog`. Some exist only on certain clients.

## Project layout

Every client has its own isolated file tree under `src/<Client>/`. No Lua file
is shared between clients, so changing one client cannot break another. Only
`Media/` and `Libs/` are shared.

```
src/
  Mainline/   Retail
  Forever/    WoW Forever (Classic)
  Vanilla/    Vanilla
  TBC/        TBC
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

- Discord: https://discord.gg/HTgSf7Bjy8
- Issues: https://github.com/NeeRgY/Nucleus/issues
- Ko-fi: https://ko-fi.com/neergy

## License

All rights reserved. You may modify the addon for private use only and may
not redistribute it. See `LICENSE.txt`.
