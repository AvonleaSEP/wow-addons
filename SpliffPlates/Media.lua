local _, Addon = ...

---------------------------------------------------------------------------------------------------
-- Imported functions and constants
---------------------------------------------------------------------------------------------------

-- Lua APIs

-- WoW APIs

-- ThreatPlates APIs
local Media = LibStub("LibSharedMedia-3.0")

--local koKR, ruRU, zhCN, zhTW, western = Media.LOCALE_BIT_koKR, Media.LOCALE_BIT_ruRU, Media.LOCALE_BIT_zhCN, Media.LOCALE_BIT_zhTW, Media.LOCALE_BIT_western

Addon.PATH_ARTWORK = "Interface\\Addons\\SpliffPlates\\Artwork\\"

---------------------------------------------------------------------------------------------------
-- Register media files that ThreatPlates needs at least (because of default settings)
---------------------------------------------------------------------------------------------------

---------------------------------------------------------------------------------------------------
-- Bar textures
---------------------------------------------------------------------------------------------------
Media:Register("statusbar", "ThreatPlatesBar", [[Interface\Addons\SpliffPlates\Artwork\TP_BarTexture.tga]])
Media:Register("statusbar", "ThreatPlatesEmpty", [[Interface\Addons\SpliffPlates\Artwork\Empty.tga]])
Media:Register("statusbar", "Aluminium", [[Interface\Addons\SpliffPlates\Artwork\Aluminium.tga]])
Media:Register("statusbar", "Smooth", [[Interface\Addons\SpliffPlates\Artwork\Smooth.tga]])

---------------------------------------------------------------------------------------------------
-- Fonts
---------------------------------------------------------------------------------------------------
Media:Register("font", "Accidental Presidency",[[Interface\Addons\SpliffPlates\Fonts\Accidental Presidency.ttf]])
Media:Register("font", "Cabin",[[Interface\Addons\SpliffPlates\Fonts\Cabin.ttf]]) --, koKR + ruRU + zhCN + zhTW + western)

---------------------------------------------------------------------------------------------------
-- Borders
---------------------------------------------------------------------------------------------------
Media:Register("border", "ThreatPlatesBorder",[[Interface\Addons\SpliffPlates\Artwork\TP_WhiteSquare.tga]])

-- Test borders
--Media:Register("border", "TP_Border_1px", [[Interface\Addons\SpliffPlates\Artwork\TP_Border_1px.tga]])
--Media:Register("border", "TP_Border_2px", [[Interface\Addons\SpliffPlates\Artwork\TP_Border_2px.tga]])
--Media:Register("border", "TP_Border_3px", [[Interface\Addons\SpliffPlates\Artwork\TP_Border_3px.tga]])
--Media:Register("border", "TP_Border_4px", [[Interface\Addons\SpliffPlates\Artwork\TP_Border_4px.tga]])
--Media:Register("border", "TP_Threat", [[Interface\Addons\SpliffPlates\Artwork\TP_Threat.tga]])
