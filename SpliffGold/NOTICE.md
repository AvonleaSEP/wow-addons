# Spliff Gold

Spliff Gold is a fork of **Accountant Classic** v2.30.03 by **arith** and **kamusis**
(itself based on the original Accountant by Sabaki, later updated by Shadow and Rophy). Accountant Classic is
licensed under the GNU General Public License, version 2. Spliff Gold is distributed
under the same licence: see `LICENSE`.

The rest of the wow-addons repository is MIT licensed; this folder is not.

## What came from Accountant Classic

- `History.lua`: Accountant Classic's history ledger (`Core/History.lua`), nearly
  unchanged: daily, hourly and per-zone money buckets for every character, and the
  list of recent money changes.
- `Tracker.lua`: the way Accountant Classic decides where money came from or went
  (`Core/Core.lua` and `Core/Constants.lua`): which window is open when the money
  changes, auction house invoices in the mailbox, repair mode, bank slot purchases,
  shared loot messages, and money changes made while the addon wasn't running.
- The categories and the Session / Today / Week / Month / Year / Total periods.

## What changed

- Saved data renamed: `Accountant_ClassicHistory` is now `SpliffGoldHistory`;
  `SpliffGoldDB` holds the lifetime totals, the all-time zone totals and settings.
- No Ace3 or other libraries: plain events and `hooksecurefunc` hooks.
- The classic per-period tables (Day, PrvDay, Week ...) are gone. Every period
  except Session and All time is read from the history ledger; All time is kept as a
  running total per character and category.
- On first load it copies your Accountant Classic data (the history ledger, the
  lifetime totals and the all-time zone totals) when Accountant Classic is installed.
- A new window, the Money Book, in Spliffbars' look, replaces Accountant Classic's
  window, minimap button and data broker.
- Opened from the Spliffbars Gold bar, `/moneybook` or `/mb`; options in `/spliffbars`.
- Warband and garrison categories are left out (this client has neither).
