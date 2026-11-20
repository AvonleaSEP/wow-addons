# Spliff's WoW Forever addons

Addons for WoW Forever (interface 16001). Each folder is one addon.

| Addon | What it does |
|---|---|
| **Spliffbars** | The hub of the package: vertical XP and reputation bars with a leveling journal, a gold goal bar, a flight timer, weapon and trade skill bars with skill-up motes, and loot effects. Options: `/spliffbars` |
| **SpliffHunter** | Hunter tools in place of macros (a Spliffbars module; its page is `/hunter`). Does nothing on other classes |
| **SpliffFrames** | Unit frames (you, your target, its target) in Spliffbars' look. A Spliffbars module: switch it on in `/spliffbars` > Modules |
| **SpliffGold** | The Money Book: where your gold comes from and goes, by day, category, zone and character. Click the Gold bar or `/mb`. A Spliffbars module, forked from Accountant Classic, so this folder is GPLv2 (see its `NOTICE.md`) |
| **DamageBar** | Your damage split by ability, best-in-a-fight records |
| **HuntTarget** | Hunt key (target, skull, chosen ability) and Tab Mark (next enemy, next mark) |
| **MacroBook** | Keeps a set of warrior macros up to date; range tint on the Shoot button |
| **CursorCues** | Icons at your mouse for missing buffs, ready abilities and tracking (`/cues`) |
| **EmoteWheel** | Hold F for a wheel of emotes; point at one and let go |
| **WeaponIndicator** | What you're holding ("Axe and Shield"); click it to apply a stone or cast Fishing |
| **BagWheel** | Your Baganator categories in a ring at the cursor, with cooldowns; click to use |
| **BagButton** | One bag icon showing your free slots; click to open your bags |
| **MinimapMenu** | A gear button on the minimap with the game's menu in a drop-down |
| **NewSpellBar** | Puts each spell you learn on Action Bar 5's first empty button (skips passives and ones already on a bar). `/newspells` |
| **MountRing** | A 28-yard ring on the minimap: anything inside is too close to bother mounting for. Tap its key to toggle, hold to peek. `/mountring` |
| **SpliffPlates** | Nameplates: a copy of Threat Plates to build on (`/splates`), plus quest progress ("3/8") on the mobs your quests need. GPL, not MIT: see below |
| **DungeonQuests** | A checklist of every dungeon's quests: which you have, who gives them and where (map pin), and what comes first (`/dq`; needs Questie) |

Most of them move and set up in Edit Mode (Esc > Edit Mode).

**SpliffPlates is GPL, not MIT.** It's a copy of **Threat Plates** 13.3.8 by Suicidal Katt and Blacksalsify ([github.com/Backupiseasy/ThreatPlates](https://github.com/Backupiseasy/ThreatPlates)), renamed and built on. Threat Plates is under the GNU General Public License, so SpliffPlates is too: see `SpliffPlates/LICENSE` and `SpliffPlates/NOTICE.md` (credits, and what was changed). The MIT licence at the top of this repository covers the other addons here, not SpliffPlates.

These addons were made with the help of Claude, Anthropic's AI assistant.

## Installing (for friends)

1. Download **SpliffAddons-Updater.zip** from the [latest release](../../releases/latest) and unzip it anywhere (say, your Desktop).
2. Double-click **Update-SpliffAddons.bat**. It finds your WoW Forever folder (or asks once), downloads the latest addons and installs them.
3. Run it again any time to update.

New addons need a full WoW restart; updates only need `/reload`.

## Publishing a version (for Spliff)

```
git tag v1.0.1
git push --tags
```

GitHub builds the zips and makes the release automatically.

## Third-party code

Some addons bundle [LibStub](https://www.wowace.com/projects/libstub) and [LibEditMode](https://github.com/p3lim-wow/LibEditMode) by p3lim, under their own licences (see each `Libs` folder).
