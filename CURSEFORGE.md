# Publishing on CurseForge

Each addon is its own CurseForge project. Once set up, every release
(`git tag v1.x.y` + `git push --tags`, or telling Claude "release it")
uploads the addons that changed to their CurseForge pages automatically.

MacroBook is not published: it writes Spliff's own warrior macros into
whoever installs it (replacing any macros with the same names).

## One-time setup

1. **Account**: sign up at https://www.curseforge.com (top right).
2. **A project per addon**: at https://authors.curseforge.com choose
   **Create Project**, game **World of Warcraft**, and fill it in from the
   sections below (name, summary, description, category). For the licence,
   **MIT** is the usual choice for addons (or "All Rights Reserved" to keep
   full control). Add a screenshot as the logo if you like.
   After saving, note the **Project ID** (shown on the project page, in the
   "About" box).
3. **API token** (lets the release upload files): at
   https://authors.curseforge.com/account/api-tokens make a token, then in
   a terminal run this and paste the token when it asks:

   ```
   gh secret set CF_API_KEY --repo AvonleaSEP/wow-addons
   ```
4. **Project IDs**: put each ID into `curseforge.json` in place of `null`
   (or give them to Claude). The next release uploads those addons.

The first file of each new project is checked by a CurseForge moderator
before it's public (usually a day or two). Later updates go live quickly.
Uploads are tagged for WoW Forever (game version 1.60.1).

---

## Page texts

### Spliffbars
**Summary:** Vertical XP and reputation bars, a gold goal bar, and weapon and trade skill bars with sparkly skill-up effects.

**Category:** HUD / Experience

**Description:**
Bars for the long haul, each one movable and set up in Edit Mode (Esc > Edit Mode).

- **XP and reputation**: slim vertical bars down the left edge with a smooth fill and 5% ticks. Hover for a timeline of your quests, kills, discoveries, playtime milestones, deaths and close calls, plus a preview of the XP your finished quests will give.
- **Gold goal bar**: set a goal (`/spliffbars goal 250`) and watch a glossy gold bar fill toward it. Hover for today, this session, gold per hour and your records. Looted coins fly into it.
- **Weapon and trade skill bars**: tiny bars with icons. Trade bars wear the game's own animated profession art. Click a trade skill to open it, a weapon skill to open your skills.
- **Skill-ups**: a mote of light flies from your cursor into the skill's bar and bursts. Learning a recipe sends a swarm. Every profession has its own colour.
- **Loot**: mining, herbs, skinning and fishing catches fly from your cursor into your bag; quest items fly to Questie's tracker; green-or-better drops to your bag.

`/spliffbars` lists the commands, including tests for each effect.

### DamageBar
**Summary:** One bar showing your damage split by ability, with your best fights as records.

**Category:** Combat

**Description:**
A single bar split into coloured pieces, one per ability, sized by its share of your damage. It adds up across fights and resets how you choose: after time out of combat, each fight, on zone change, each login, or never (right-click to clear). Hover for the full list. A gold box at the end holds your best of the day, with all-time records in the tooltip.

Reads the game's own damage meter. Move and size it in Edit Mode.

### HuntTarget
**Summary:** Type a mob name, press one key to target it, skull it and charge. Plus Tab Mark: mark a whole pack in one key.

**Category:** Combat

**Description:**
- **Hunt key**: type up to three mob names in the box (or Alt+click a mob). Your Hunt key targets the nearest one, marks it with a skull and uses your chosen ability: Charge (Battle Stance first), Shoot/Throw, just mark, or any spell (`/hunt ability <spell>`).
- **Tab Mark**: each press targets the next enemy and gives it the next mark: skull, cross, square, moon and on to star. It starts over after each fight.
- **Follow**: Alt+click an ally to set up following them.

Set the keys in Options > Keybindings > AddOns. Works in combat.

### DungeonQuests
**Summary:** A checklist of every dungeon's quests: which you have, who gives them, where (map pin) and what to do first.

**Category:** Quests & Leveling

**Description:**
`/dq` opens a panel listing every dungeon, easiest first, with how many of its quests you have. Pick one to see all its quests with:

- your status: done, in your log, pick it up, too low, or needs a quest first;
- who starts it and where, with a **Map** button that pins them on your world map;
- the quests you need first, each clickable to see where it starts.

Filtered to your race and class. Requires Questie (it reads Questie's quest database).

### SpliffPlates
**Summary:** Quest progress like "3/8" on the nameplates of mobs your quests need.

**Category:** Quests & Leveling / Unit Frames

**Description:**
A small gold "3/8" under the health bar of every mob that counts toward one of your quests, and a green tick once that objective is done. Only objectives in your own quest log count. Turn on "Always Show Nameplates" to see it out of combat. Works alongside Questie's nameplate icon. `/plates` turns it on and off.

### CursorCues
**Summary:** Icons at your mouse for missing buffs, ready abilities, tracking, and targets in range.

**Category:** HUD / Buffs & Debuffs

**Description:**
Little icons that follow your cursor, each a "cue" you set up in `/cues`:

- a buff missing on you (e.g. Battle Shout, food);
- your buff missing on the group;
- an ability ready (e.g. Overpower / Revenge);
- tracking off (Find Minerals / Herbs);
- your target in range of a spell: a throwing knife on your pointer while you can Throw.

Each cue has its own timing (in combat, out, always), look (steady, pulse, flash), size and spot.

### WeaponIndicator
**Summary:** Shows what you're holding ("Axe and Shield"); click it to apply a sharpening stone or start fishing.

**Category:** Unit Frames / Miscellaneous

**Description:**
A small badge with your weapon icons and a label like "Two-Hand Axe", "Axe and Shield" or "Dual Daggers", coloured by what you're holding. Use a sharpening stone, weightstone or oil and the icons glow: click one to put it on that weapon. With a fishing pole in hand, a click casts Fishing. Hover for the weapon's tooltip. Size, spacing, text position, font and colour are all in Edit Mode.

### BagWheel
**Summary:** Your Baganator categories in a ring at your cursor; hover for the items, click to use. Works in combat.

**Category:** Bags & Inventory

**Description:**
Press your key and a ring of your Baganator custom categories opens at the cursor. Hover a category to see its items in your bags, click one to use it. Clicking a category's own icon uses its item you use most. Cooldowns show on every button. Sharpening stones and weightstones go straight onto your main-hand weapon (Shift: off hand). Choose which categories show in Options > AddOns > Bag Wheel.

Uses your Baganator settings (optional dependency).

### BagButton
**Summary:** One bag icon showing your free bag slots; click to open your bags.

**Category:** Bags & Inventory

**Description:**
A single movable bag button that shows how many bag slots you have free and opens your bags (whatever bag addon you use). It can hide the game's row of bag buttons. Move and size it in Edit Mode.

### MinimapMenu
**Summary:** A gear button on the minimap with the game menu in a drop-down. Can hide the menu bar.

**Category:** Map & Minimap

**Description:**
A gear button on the minimap that opens the game's menu (character, spellbook, talents, professions and the rest) as a tidy drop-down, so you can hide the menu bar at the bottom of the screen. Works in combat.

### EmoteWheel
**Summary:** Hold F for a wheel of emotes; point at one and let go.

**Category:** Roleplay / Chat

**Description:**
Hold the key (F by default) and a wheel of emotes opens at your cursor: dance, laugh, cheer, cry, kneel, point and more. Point at one and let go to do it. Change the key in Options > Keybindings > AddOns.
