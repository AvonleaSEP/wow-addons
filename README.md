# Spliff's WoW Forever addons

Addons for WoW Forever (interface 16001). Each folder is one addon.

| Addon | What it does |
|---|---|
| **Spliffbars** | Vertical XP and reputation bars with a timeline, a gold goal bar, weapon and trade skill bars with skill-up motes, and gathered loot flying to your bag |
| **DamageBar** | Your damage split by ability, best-in-a-fight records |
| **HuntTarget** | Hunt key (target, skull, chosen ability) and Tab Mark (next enemy, next mark) |
| **MacroBook** | Keeps a set of warrior macros up to date; range tint on the Shoot button |
| **CursorCues** | Icons at your mouse for missing buffs, ready abilities and tracking (`/cues`) |
| **EmoteWheel** | Hold F for a wheel of emotes; point at one and let go |
| **WeaponIndicator** | What you're holding ("Axe and Shield"); click it to apply a stone or cast Fishing |
| **BagWheel** | Your Baganator categories in a ring at the cursor, with cooldowns; click to use |
| **BagButton** | One bag icon showing your free slots; click to open your bags |
| **MinimapMenu** | A gear button on the minimap with the game's menu in a drop-down |
| **SpliffPlates** | Quest progress ("3/8") on the nameplates of mobs your quests need (`/plates`) |
| **DungeonQuests** | A checklist of every dungeon's quests: which you have, who gives them and where (map pin), and what comes first (`/dq`; needs Questie) |

Most of them move and set up in Edit Mode (Esc > Edit Mode).

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
