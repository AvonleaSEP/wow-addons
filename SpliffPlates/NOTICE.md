# Spliff Plates

Spliff Plates is a copy of **Threat Plates 13.3.8** (folder `TidyPlates_ThreatPlates`)
by **Suicidal Katt and Blacksalsify**, building on **danltiger**'s Tidy Plates, with
quest handling code credited to Tosaido (QuestMobs). Their source and releases:
https://github.com/Backupiseasy/ThreatPlates

Threat Plates states its licence as the GNU General Public License (its `.toc`:
`X-License: GNU General Public License`) without naming a version. Spliff Plates
is distributed under the same licence; `LICENSE` holds the text of the current
version (GPL v3). Everything here, Threat Plates' code and the additions below,
may be copied, changed and shared under those terms, with its source.

## Changed from Threat Plates 13.3.8 (Devon, November 2026)

- Renamed so it can sit beside the real Threat Plates: the folder and `.toc`
  (`SpliffPlates`), its paths (`Interface\AddOns\SpliffPlates\...`), its saved
  settings (`SpliffPlatesThreatDB`) and its commands (`/splates`, `/splatesdps`,
  `/splatestank`, `/splatestoggle`, `/splatesverbose`).
- `.toc`: title, notes, author line and version; Threat Plates' CurseForge,
  WoWInterface and Wago project IDs removed (so updaters don't replace this copy).
- Added `QuestProgress.lua`: quest progress ("3/8") on the plates of mobs your
  quests need, and its page in Spliffbars' options.
- `Constants.lua`: the aura rows sit higher by default (debuffs 16 above the
  health bar instead of 8, buffs on top of them), clear of the name.
