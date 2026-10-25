--==============================================================================
-- RC PARTY ORBS 
-- Version: 2.3.0
-- Author: Raw Card
-- Notes: Replacement for party frames with animated fire orbs.
-- Features: Threat borders, debuff colors, click-to-dispel, click-to-rez
--           Configurable modifier key, adjustable font size
-- Compatibility: Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era, WoW Forever
--==============================================================================

-- Create event frame HERE at the very top so ADDON_LOADED isn't missed.
-- The full OnEvent handler is defined later but we need the frame registered now.
RCPartyOrbs_EventFrame = CreateFrame("Frame")
RCPartyOrbs_EventFrame:RegisterEvent("ADDON_LOADED")
RCPartyOrbs_EventFrame:RegisterEvent("VARIABLES_LOADED")
RCPartyOrbs_EventFrame:RegisterEvent("PLAYER_LOGIN")
RCPartyOrbs_EventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

-----------------------------------------------------------
-- CLIENT COMPATIBILITY
-- Retail (11.0+) and WoW Forever removed the old aura functions; rebuild them
-- from C_UnitAuras where missing (locals: other addons never see them).
-- Those clients also hide some combat values from addons ("secret values":
-- party health, auras...); they can be shown but not compared or used in math.
-----------------------------------------------------------
local function auraTuple(a)
    if not a then return nil end
    return a.name, a.icon, a.applications, a.dispelName, a.duration, a.expirationTime, a.sourceUnit,
        a.isStealable, a.nameplateShowPersonal, a.spellId
end
local UnitBuff = UnitBuff or function(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        return auraTuple(C_UnitAuras.GetBuffDataByIndex(unit, index, filter))
    end
end
local UnitDebuff = UnitDebuff or function(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        return auraTuple(C_UnitAuras.GetDebuffDataByIndex(unit, index, filter))
    end
end
function RCPartyOrbs_Secret(v)
    return issecretvalue ~= nil and issecretvalue(v) or false
end
-- a yes/no answer we can trust (a hidden one counts as "no")
function RCPartyOrbs_True(v)
    return not RCPartyOrbs_Secret(v) and v and true or false
end
-- a readable 0-100 percentage of a unit's health or power (works with hidden values)
function RCPartyOrbs_Percent(kind, unit, powerType)
    local curve = CurveConstants and CurveConstants.ScaleTo100
    local ok, pct = false, nil
    if kind == "health" and UnitHealthPercent then
        ok, pct = pcall(UnitHealthPercent, unit, false, curve)
    elseif kind == "power" and UnitPowerPercent then
        ok, pct = pcall(UnitPowerPercent, unit, powerType, curve)
    end
    if not ok or type(pct) ~= "number" or RCPartyOrbs_Secret(pct) then return nil end
    if not curve then pct = pct * 100 end
    return pct
end

-----------------------------------------------------------
-- BLIZZARD BUG WORKAROUND
-- Stub for missing function that causes errors in Classic/MoP raids
-----------------------------------------------------------
if not UnitFrameManaCostPredictionBars_Update then
    UnitFrameManaCostPredictionBars_Update = function() end
end

-----------------------------------------------------------
-- VERSION DETECTION & COMPATIBILITY LAYER
-----------------------------------------------------------
local tocVersion = 0
if GetBuildInfo then
    local _, _, _, interfaceVersion = GetBuildInfo()
    tocVersion = interfaceVersion or 0
end

-- Version flags
local RCPartyOrbs_Version = {
    tocVersion = tocVersion,
    isRetail = tocVersion >= 100000,                              -- Dragonflight+
    isMoP = tocVersion >= 50000 and tocVersion < 60000,          -- MoP Remix
    isCata = tocVersion >= 40000 and tocVersion < 50000,         -- Cataclysm Classic
    isWrath = tocVersion >= 30000 and tocVersion < 40000,        -- Wrath Classic
    isTBC = tocVersion >= 20000 and tocVersion < 30000,          -- TBC Classic
    isClassicEra = tocVersion < 20000 and tocVersion > 0,        -- Classic Era / Hardcore
}

-- Compatibility wrappers for APIs that differ between versions
local Compat = {}

-- C_Timer compatibility (exists in most versions but let's be safe)
Compat.After = C_Timer and C_Timer.After or function(delay, func)
    local frame = CreateFrame("Frame")
    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= delay then
            self:SetScript("OnUpdate", nil)
            func()
        end
    end)
end

-- GetNumGroupMembers compatibility
Compat.GetNumGroupMembers = GetNumGroupMembers or function()
    if IsInRaid() then
        return GetNumRaidMembers and GetNumRaidMembers() or 0
    else
        return (GetNumPartyMembers and GetNumPartyMembers() or 0) + 1
    end
end

-- UnitGroupRolesAssigned compatibility (not in Classic Era)
Compat.UnitGroupRolesAssigned = function(unit)
    if UnitGroupRolesAssigned then
        return UnitGroupRolesAssigned(unit)
    end
    return "NONE"  -- Classic Era doesn't have roles
end

-- CompactPartyFrame compatibility (doesn't exist in Classic)
Compat.HideCompactPartyFrame = function()
    if CompactPartyFrame then
        CompactPartyFrame:Hide()
        CompactPartyFrame:UnregisterAllEvents()
    end
end

-- IsInRaid compatibility
Compat.IsInRaid = IsInRaid or function()
    return GetNumRaidMembers and GetNumRaidMembers() > 0
end

-- GetSpellInfo compatibility (changed in Dragonflight)
Compat.GetSpellInfo = function(spellID)
    if C_Spell and C_Spell.GetSpellInfo then
        local info = C_Spell.GetSpellInfo(spellID)
        if info then
            return info.name, nil, info.iconID, info.castTime, info.minRange, info.maxRange, info.spellID
        end
        return nil
    elseif GetSpellInfo then
        return GetSpellInfo(spellID)
    end
    return nil
end

-- UnitAura/UnitDebuff compatibility
Compat.UnitDebuff = UnitDebuff or function(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetDebuffDataByIndex then
        return auraTuple(C_UnitAuras.GetDebuffDataByIndex(unit, index, filter))
    end
    if UnitAura then
        return UnitAura(unit, index, "HARMFUL" .. (filter or ""))
    end
    return nil
end

Compat.UnitBuff = UnitBuff or function(unit, index, filter)
    if C_UnitAuras and C_UnitAuras.GetBuffDataByIndex then
        return auraTuple(C_UnitAuras.GetBuffDataByIndex(unit, index, filter))
    end
    if UnitAura then
        return UnitAura(unit, index, "HELPFUL" .. (filter or ""))
    end
    return nil
end

-- Print version info on load (debug)
-- print("|cFF00FF00RCPartyOrbs|r: Detected WoW version " .. tocVersion .. 
--       (RCPartyOrbs_Version.isRetail and " (Retail)" or 
--        RCPartyOrbs_Version.isMoP and " (MoP)" or
--        RCPartyOrbs_Version.isCata and " (Cata Classic)" or
--        RCPartyOrbs_Version.isWrath and " (Wrath Classic)" or
--        RCPartyOrbs_Version.isClassicEra and " (Classic Era)" or " (Unknown)"))

-----------------------------------------------------------
-- RETAIL COMPATIBILITY: UIDropDownMenu stubs
-- UIDropDownMenuTemplate and all UIDropDownMenu_* functions were removed in 10.0
-- These stubs prevent nil errors. The frames (RCPartyOrbsSwirlDropdown etc.)
-- won't be created from XML in Retail (template missing), but init functions
-- guard with "if not d then return end" so they silently skip.
-- The ToggleDropDownMenu for right-click unit menus is replaced below.
-----------------------------------------------------------
if not UIDropDownMenu_Initialize then
    UIDropDownMenu_Initialize = function(frame, func, menuType) end
end
if not UIDropDownMenu_CreateInfo then
    UIDropDownMenu_CreateInfo = function() return {} end
end
if not UIDropDownMenu_AddButton then
    UIDropDownMenu_AddButton = function(info, level) end
end
if not UIDropDownMenu_AddSeparator then
    UIDropDownMenu_AddSeparator = function(info, level) end
end
if not UIDropDownMenu_SetText then
    UIDropDownMenu_SetText = function(frame, text) end
end
if not UIDropDownMenu_GetText then
    UIDropDownMenu_GetText = function(frame) return "" end
end
if not ToggleDropDownMenu then
    ToggleDropDownMenu = function(level, value, dropDownFrame, anchorName, xOffset, yOffset) end
end

-- Determine the unit popup "which" type for both systems
local function GetUnitMenuType(unit)
    if UnitIsUnit(unit, "player") then
        return "SELF"
    elseif unit:match("^party%d$") then
        return "PARTY"
    elseif unit:match("^raid%d+$") then
        return "RAID"
    elseif unit:match("^pet$") then
        return "PET"
    elseif unit:match("^target$") then
        return UnitIsPlayer(unit) and "PLAYER" or "TARGET"
    elseif unit:match("^focus$") then
        return UnitIsPlayer(unit) and "PLAYER" or "FOCUS"
    elseif UnitIsPlayer(unit) then
        return "PLAYER"
    end
    return "PLAYER"
end

-- Safe wrapper for showing unit menus (handles Retail's different API)
-- Retail 10.0+ uses the new Blizzard_Menu system (MenuUtil / Menu.OpenContextMenu)
-- Classic/Wrath/Cata/MoP use ToggleDropDownMenu with PartyMemberFrameDropDown frames
Compat.ShowUnitMenu = function(self, unit)
    if not unit then return end

    local menuType = GetUnitMenuType(unit)

    if RCPartyOrbs_Version.isRetail and MenuUtil and MenuUtil.CreateContextMenu then
        -- Retail 10.0+ (Dragonflight / The War Within)
        -- Store unit info on the anchor frame so the menu system's contextData picks it up
        self.unit = unit
        self.name = UnitName(unit)

        -- The tag MENU_UNIT_<TYPE> selects which Blizzard-managed menu to show.
        -- PARTY, RAID, SELF, PET, PLAYER are all valid unit popup tags.
        local tag = "MENU_UNIT_" .. menuType

        pcall(MenuUtil.CreateContextMenu, self, function(ownerRegion, rootDescription)
            rootDescription:SetTag(tag)
        end)
        return
    end

    -- Classic / Wrath / Cata / MoP: use the old ToggleDropDownMenu system
    local dropdown = nil
    if menuType == "SELF" then
        dropdown = PlayerFrameDropDown
    elseif menuType == "PET" then
        dropdown = PetFrameDropDown
    elseif unit:match("^party%d$") then
        dropdown = _G["PartyMemberFrame" .. unit:match("%d+") .. "DropDown"]
        if not dropdown then dropdown = PartyMemberFrame1DropDown end
    elseif unit:match("^raid%d+$") then
        dropdown = _G["RaidUnitFrameDropDown"]
    elseif unit:match("^target$") then
        dropdown = TargetFrameDropDown
    elseif unit:match("^focus$") then
        dropdown = _G["FocusFrameDropDown"]
    end

    if not dropdown then dropdown = PartyMemberFrame1DropDown end

    if dropdown then
        dropdown.unit = unit
        ToggleDropDownMenu(1, nil, dropdown, self, 0, 0)
    end
end

-- ColorPicker compatibility: Dragonflight (10.0+) changed to table-based OpenColorPicker
-- Pre-Dragonflight uses direct property assignment on ColorPickerFrame
Compat.OpenColorPicker = function(options)
    -- options: { r, g, b, a, hasOpacity, func, cancelFunc }
    if RCPartyOrbs_Version.isRetail and ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        -- Dragonflight+ API
        local info = {
            swatchFunc  = options.func,
            opacityFunc = options.func,
            cancelFunc  = options.cancelFunc,
            r = options.r, g = options.g, b = options.b,
            opacity = options.a ~= nil and (1 - options.a) or 0,
            hasOpacity = options.hasOpacity,
            previousValues = { r=options.r, g=options.g, b=options.b, opacity = options.a ~= nil and (1-options.a) or 0 },
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
    else
        -- Classic / pre-Dragonflight API
        ColorPickerFrame.hasOpacity = options.hasOpacity
        ColorPickerFrame.opacity = options.a ~= nil and (1 - options.a) or 0
        ColorPickerFrame.previousValues = options.previousValues
        ColorPickerFrame.func = options.func
        ColorPickerFrame.swatchFunc = options.func
        ColorPickerFrame.cancelFunc = options.cancelFunc
        ColorPickerFrame:SetColorRGB(options.r, options.g, options.b)
        ColorPickerFrame:Show()
    end
end

-- Safe CompactPartyFrame hiding (it's a protected frame in Retail)
Compat.HideCompactPartyFrame = function()
    if CompactPartyFrame then
        pcall(function() CompactPartyFrame:Hide() end)
        pcall(function() CompactPartyFrame:UnregisterAllEvents() end)
    end
    -- Retail 10.0+ uses PartyFrame
    if PartyFrame then
        pcall(function() PartyFrame:Hide() end)
        pcall(function() PartyFrame:UnregisterAllEvents() end)
    end
end

-----------------------------------------------------------
-- 1. CONSTANTS AND DEFAULTS
-----------------------------------------------------------
local FRAME_COUNT = 29
local FRAME_RATE = 0.05  -- seconds per frame (20 fps)
local ORB_SIZE = 80
local ORB_SPACING = 15

-- Tables to store our frames and states
local orbFrames = {}
local testMode = false
local debugMode = false 
local testPartyData = {}

-- Create the database if it doesn't exist
RCPartyOrbsDB = RCPartyOrbsDB or {}

-- Swirl sets configuration for orb interiors
local SWIRL_SETS = {
    ["bubbles"] = {
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_bubbles1.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_bubbles2.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_bubbles3.tga"
    },
    ["galaxy"] = {
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_galaxy1.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_galaxy2.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_galaxy3.tga"
    },
    ["iris"] = {
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_iris1.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_iris2.tga",
        "Interface\\AddOns\\RCPartyOrbs\\images\\orb_rotation_iris3.tga"
    }
}

local currentSwirlSet = "bubbles"

-- Debuff alert sounds configuration
local DEBUFF_SOUNDS = {
    ["default"] = { name = "Default (Ready Check)", file = nil },  -- Uses SOUNDKIT.READY_CHECK
    ["affliction"] = { name = "Affliction Alert", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\AfflictionAlert.ogg" },
    ["daboo"] = { name = "Daboo", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\daboo.mp3" },
    ["ergh"] = { name = "Ergh", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\ergh.mp3" },
    ["fart1"] = { name = "Fart 1", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\fart.mp3" },
    ["fart2"] = { name = "Fart 2", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\fart (1).mp3" },
    ["friday13"] = { name = "Friday the 13th", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\friday_the_13th.mp3" },
    ["haha"] = { name = "Ha-Ha", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\ha-ha.mp3" },
    ["hello"] = { name = "Hello", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\hello.mp3" },
    ["heylisten"] = { name = "Hey Listen!", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\hey-listen.mp3" },
    ["knockknock"] = { name = "Knock Knock", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\knock knock.mp3" },
    ["mario1up"] = { name = "Mario 1-Up", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\mario-1up.mp3" },
    ["mariodie"] = { name = "Mario Die", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\mario-die.mp3" },
    ["notkindoforc"] = { name = "Me Not That Kind of Orc", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\me-not-that-kind-of-orc.mp3" },
    ["readytowork"] = { name = "Ready to Work", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\ready-to-work.mp3" },
    ["schovoo"] = { name = "Schovoo", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\schovoo.mp3" },
    ["sheepscream"] = { name = "Sheep Scream", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\Sheep Scream.mp3" },
    ["uhhuh"] = { name = "Uh-Huh", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\uh-huh.mp3" },
    ["wahoo"] = { name = "Wahoo!", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\wahoo.mp3" },
    ["workcomplete"] = { name = "Work Complete", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\warcraft-peon-work-complete.mp3" },
    ["work"] = { name = "Work Work", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\warcraft-peon-work.mp3" },
    ["zeldaitem"] = { name = "Zelda Item Get", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\zelda-item-get.mp3" },
    ["zeldasecret"] = { name = "Zelda Secret", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\zelda-secret.mp3" },
    ["zugzug"] = { name = "Zug Zug", file = "Interface\\AddOns\\RCPartyOrbs\\Soundkit\\zug-zug.mp3" },
}

-- Order for debuff sound dropdown display
local DEBUFF_SOUND_ORDER = {
    "default", "affliction", "daboo", "ergh", "fart1", "fart2", "friday13",
    "haha", "hello", "heylisten", "knockknock", "mario1up", "mariodie",
    "notkindoforc", "readytowork", "schovoo", "sheepscream", "uhhuh",
    "wahoo", "workcomplete", "work", "zeldaitem", "zeldasecret", "zugzug"
}

-- Default Global Database Template to prevent Startup Errors
local DB_DEFAULTS = {
    enabled = true,
    swirlSet = "bubbles",
    scale = 1.0,
    orbSize = 80,
    orbSpacing = 20,
    targetOrbSpacing = 15,  -- Spacing between party member and their target
    targetOrbScale = 75,  -- Target orb size as percentage (75 = 75% of normal orb size)
    showHealthPercentage = true,
    showHealthValue = true,
    showManaValue = true,
    showName = true,
    showThreatBorders = true,
    showDebuffColors = true,
    showPlayerOrbs = true,
    showPartyTargets = true,  -- Show party member target orbs (master toggle)
    showHelpOnLogin = true,
    framesLocked = true,
    partyOrientation = "horizontal",  -- "horizontal" or "vertical"
    fireColor = {r = 1, g = 1, b = 1},
    fireBorderColor = {r=1, g=0, b=0, a=1},
    greenBorderColor = {r=0, g=1, b=0, a=1},
    yellowBorderColor = {r=1, g=1, b=0, a=1},
    minimapButtonAngle = 45,
    clickModifier = "shift",  -- Modifier key for dispel/rez: "shift", "alt", or "ctrl"
    fontScale = 100,  -- Font size as percentage (50-200%)
    -- Individual orb visibility settings
    showPlayerOrb = true,
    showParty1Orb = true,
    showParty2Orb = true,
    showParty3Orb = true,
    showParty4Orb = true,
    showTargetOrb = true,
    showParty1Target = true,
    showParty2Target = true,
    showParty3Target = true,
    showParty4Target = true,
    showCastBars = true,  -- Show cast bars below orbs
    showLevel = true,     -- Show level after name
    showRoleIcon = true,  -- Show tank/healer/dps icon
    playDebuffSound = true, -- Play sound when debuff detected
    debuffSound = "affliction", -- Selected debuff alert sound
    debugMode = false
}

-- Class Color mapping for unit health bars (defined early for use in color functions)
local CLASS_COLORS = {
    ["WARRIOR"]     = {0.78, 0.61, 0.43},
    ["PALADIN"]     = {0.96, 0.55, 0.73},
    ["HUNTER"]      = {0.67, 0.83, 0.45},
    ["ROGUE"]       = {1.0, 0.96, 0.41},
    ["PRIEST"]      = {1.0, 1.0, 1.0},
    ["DEATHKNIGHT"] = {0.77, 0.12, 0.23},
    ["SHAMAN"]      = {0.0, 0.44, 0.87},
    ["MAGE"]        = {0.41, 0.8, 0.94},
    ["WARLOCK"]     = {0.58, 0.51, 0.79},
    ["MONK"]        = {0.0, 1.0, 0.59},
    ["DRUID"]       = {1.0, 0.49, 0.04},
    ["DEMONHUNTER"] = {0.64, 0.19, 0.79},
    ["EVOKER"]      = {0.2, 0.58, 0.5},
}

-- Character-specific color key (set on PLAYER_LOGIN)
local characterColorKey = nil

-- Get character-specific color from database
local function GetCharacterColor(colorType)
    if not characterColorKey or not RCPartyOrbsDB.characterColors then return nil end
    local charColors = RCPartyOrbsDB.characterColors[characterColorKey]
    if charColors and charColors[colorType] then
        return charColors[colorType]
    end
    return nil
end

-- Set character-specific color in database
local function SetCharacterColor(colorType, color)
    if not characterColorKey then return end
    RCPartyOrbsDB.characterColors = RCPartyOrbsDB.characterColors or {}
    RCPartyOrbsDB.characterColors[characterColorKey] = RCPartyOrbsDB.characterColors[characterColorKey] or {}
    RCPartyOrbsDB.characterColors[characterColorKey][colorType] = color
end

-- Get default power color based on class for health, or standard colors for power types
local function GetDefaultColor(colorType, playerClass)
    if colorType == "health" then
        -- Default to class color
        local classColor = CLASS_COLORS[playerClass]
        if classColor then
            return {r = classColor[1], g = classColor[2], b = classColor[3], a = 1}
        end
        return {r = 0.0, g = 1.0, b = 0.0, a = 1}  -- Fallback green
    elseif colorType == "mana" then
        return {r = 0.2, g = 0.7, b = 1.0, a = 1}
    elseif colorType == "rage" then
        return {r = 1.0, g = 0.3, b = 0.3, a = 1}
    elseif colorType == "energy" then
        return {r = 1.0, g = 1.0, b = 0.3, a = 1}
    elseif colorType == "focus" then
        return {r = 1.0, g = 0.5, b = 0.25, a = 1}
    elseif colorType == "runic" then
        return {r = 0.3, g = 0.9, b = 1.0, a = 1}
    elseif colorType == "chi" then
        return {r = 0.7, g = 1.0, b = 0.8, a = 1}
    end
    return {r = 1, g = 1, b = 1, a = 1}
end

-- Initialize character color key (call on PLAYER_LOGIN)
local function InitializeCharacterColors()
    local name = UnitName("player")
    local realm = GetRealmName()
    characterColorKey = name .. "-" .. realm
    
    -- Ensure characterColors table exists
    RCPartyOrbsDB.characterColors = RCPartyOrbsDB.characterColors or {}
    
    -- Initialize character's colors table if it doesn't exist (empty - will use class color fallback)
    if not RCPartyOrbsDB.characterColors[characterColorKey] then
        RCPartyOrbsDB.characterColors[characterColorKey] = {}
    end
    
    -- Clean up any old global color settings that might interfere
    RCPartyOrbsDB.healthColor = nil
    RCPartyOrbsDB.manaColor = nil
    RCPartyOrbsDB.rageColor = nil
    RCPartyOrbsDB.energyColor = nil
    RCPartyOrbsDB.focusColor = nil
    RCPartyOrbsDB.runicColor = nil
    RCPartyOrbsDB.chiColor = nil
end

-- Global function to reset character colors to defaults
function RCPartyOrbs_ResetCharacterColors()
    if not characterColorKey then return end
    
    -- Clear all character-specific colors (will use class color fallback)
    RCPartyOrbsDB.characterColors[characterColorKey] = {}
    
    -- Force update all orbs
    if RCPartyOrbs_ForceUpdateAllOrbs then
        RCPartyOrbs_ForceUpdateAllOrbs()
    end
    
    print("|cFF00FF00RCPartyOrbs:|r Orb colors reset to class defaults for this character")
end

-- Debuff type colors for dispel indicators (use Blizzard's colors as base, with brighter versions)
local DEBUFF_COLORS = {
    ["Poison"]  = {0.0, 0.6, 0.0},    -- Green (Blizzard default)
    ["Disease"] = {0.6, 0.4, 0.0},    -- Brown (Blizzard default)
    ["Curse"]   = {0.6, 0.0, 1.0},    -- Purple (Blizzard default)
    ["Magic"]   = {0.2, 0.6, 1.0},    -- Blue (Blizzard default)
}

-- Override with Blizzard's DebuffTypeColor if available (more accurate)
if DebuffTypeColor then
    if DebuffTypeColor["Poison"] then DEBUFF_COLORS["Poison"] = {DebuffTypeColor["Poison"].r, DebuffTypeColor["Poison"].g, DebuffTypeColor["Poison"].b} end
    if DebuffTypeColor["Disease"] then DEBUFF_COLORS["Disease"] = {DebuffTypeColor["Disease"].r, DebuffTypeColor["Disease"].g, DebuffTypeColor["Disease"].b} end
    if DebuffTypeColor["Curse"] then DEBUFF_COLORS["Curse"] = {DebuffTypeColor["Curse"].r, DebuffTypeColor["Curse"].g, DebuffTypeColor["Curse"].b} end
    if DebuffTypeColor["Magic"] then DEBUFF_COLORS["Magic"] = {DebuffTypeColor["Magic"].r, DebuffTypeColor["Magic"].g, DebuffTypeColor["Magic"].b} end
end

-- Dynamic dispel list - updated when spells change
local playerDispelList = {}

-- Spell IDs for dispel abilities (MoP Classic)
-- Format: spellID = { dispelTypes = {...}, checkSpellID = spellID or nil for talent check }
local DISPEL_SPELLS = {
    -- Paladin
    [4987]  = { class = "PALADIN", types = {"Poison", "Disease"}, name = "Cleanse" },  -- Cleanse (baseline)
    [53551] = { class = "PALADIN", types = {"Magic"}, name = "Sacred Cleansing", isTalent = true },  -- Sacred Cleansing (Holy talent)
    -- Priest
    [527]   = { class = "PRIEST", types = {"Magic"}, name = "Purify" },  -- Purify (was Dispel Magic)
    [528]   = { class = "PRIEST", types = {"Disease"}, name = "Cure Disease" },  -- Cure Disease
    -- Shaman
    [51886] = { class = "SHAMAN", types = {"Curse"}, name = "Cleanse Spirit" },  -- Cleanse Spirit (baseline)
    [77130] = { class = "SHAMAN", types = {"Curse", "Magic"}, name = "Purify Spirit" },  -- Purify Spirit (Resto)
    -- Mage
    [475]   = { class = "MAGE", types = {"Curse"}, name = "Remove Curse" },  -- Remove Curse
    -- Druid
    [2782]  = { class = "DRUID", types = {"Curse", "Poison"}, name = "Remove Corruption" },  -- Remove Corruption (baseline)
    [88423] = { class = "DRUID", types = {"Curse", "Poison", "Magic"}, name = "Nature's Cure" },  -- Nature's Cure (Resto)
    -- Monk
    [115450] = { class = "MONK", types = {"Poison", "Disease", "Magic"}, name = "Detox" },  -- Detox (Mistweaver)
    [218164] = { class = "MONK", types = {"Poison", "Disease"}, name = "Detox" },  -- Detox (BM/WW)
    -- Evoker (Dragonflight+)
    [374251] = { class = "EVOKER", types = {"Poison"}, name = "Expunge" },          -- Expunge (baseline)
    [374346] = { class = "EVOKER", types = {"Poison", "Bleed"}, name = "Expunge" }, -- Expunge + Cauterize Wounds talent
}

-- Dispel spell names for click-to-dispel (primary dispel per class)
local CLASS_DISPEL_SPELLS = {
    ["PALADIN"]  = "Cleanse",
    ["PRIEST"]   = "Purify",
    ["SHAMAN"]   = "Cleanse Spirit",
    ["MAGE"]     = "Remove Curse",
    ["DRUID"]    = "Remove Corruption",
    ["MONK"]     = "Detox",
    ["EVOKER"]   = "Expunge",  -- Dragonflight+
}

-- Battle rez spells per class (MoP Classic) - combat only, no regular rez
local CLASS_REZ_SPELLS = {
    ["DRUID"]       = { combat = "Rebirth" },
    ["DEATHKNIGHT"] = { combat = "Raise Ally" },
    ["WARLOCK"]     = { combat = "Soulstone" },
    ["HUNTER"]      = { combat = "Eternal Guardian" },  -- Quilen pet ability
}

-- Get the player's battle rez spell (combat only)
local function GetPlayerRezSpell()
    local _, playerClass = UnitClass("player")
    local rezData = CLASS_REZ_SPELLS[playerClass]
    if not rezData then return nil end
    return rezData.combat
end

-- Helper function to check if a spell is known
local function IsSpellKnownByPlayer(spellID)
    -- Try multiple methods to check spell availability
    if IsSpellKnown then
        if IsSpellKnown(spellID) then return true end
    end
    if IsPlayerSpell then
        if IsPlayerSpell(spellID) then return true end
    end
    -- Check spellbook
    local name = Compat.GetSpellInfo(spellID)
    if name then
        local spellBookID = FindSpellBookSlotBySpellID and FindSpellBookSlotBySpellID(spellID)
        if spellBookID then return true end
        -- Also check by name
        local _, _, _, _, _, _, actualSpellID = Compat.GetSpellInfo(name)
        if actualSpellID == spellID then return true end
    end
    return false
end

-- Update what the player can dispel (called on login and talent changes)
local function UpdatePlayerDispels()
    wipe(playerDispelList)
    local _, playerClass = UnitClass("player")
    
    for spellID, data in pairs(DISPEL_SPELLS) do
        if data.class == playerClass then
            -- Check if player has this spell
            local hasSpell = IsSpellKnownByPlayer(spellID)
            if hasSpell then
                for _, dispelType in ipairs(data.types) do
                    playerDispelList[dispelType] = true
                end
                if debugMode then
                    print("|cFF00FF00RCPartyOrbs:|r Found dispel spell: " .. (data.name or spellID) .. " - can dispel: " .. table.concat(data.types, ", "))
                end
            end
        end
    end
    
    if debugMode then
        local dispelTypes = {}
        for k, _ in pairs(playerDispelList) do table.insert(dispelTypes, k) end
        if #dispelTypes > 0 then
            print("|cFF00FF00RCPartyOrbs:|r Player can dispel: " .. table.concat(dispelTypes, ", "))
        else
            print("|cFFFF0000RCPartyOrbs:|r Player cannot dispel anything (no dispel spells found)")
        end
    end
end

-- Offensive dispel/purge spell names for each class (removes buffs from enemies)
local CLASS_PURGE_SPELLS = {
    ["SHAMAN"]   = "Purge",
    ["PRIEST"]   = "Dispel Magic",
    ["MAGE"]     = "Spellsteal",
    ["WARLOCK"]  = "Devour Magic",  -- Felhunter ability
    ["HUNTER"]   = "Tranquilizing Shot",
}

-- Color for purgeable buffs on enemies (bright white/gold)
local PURGEABLE_BUFF_COLOR = {1.0, 0.8, 0.2}  -- Gold/yellow for stealable buffs

-- Store original colors for restoration after dispel
local originalOrbColors = {}

-- Test debuff mode
local testDebuffMode = false
local testDebuffType = nil

-----------------------------------------------------------
-- 2. UTILITY & DATA FUNCTIONS
-----------------------------------------------------------

 local function SafeGetNormalizedRealmName()
     if type(GetNormalizedRealmName) == "function" then
         return GetNormalizedRealmName()
     end
     return GetRealmName and GetRealmName() or ""
 end

 local function SafeUnitGroupRolesAssigned(unit)
     return Compat.UnitGroupRolesAssigned(unit)
 end

 local function IsInInstanceGroup()
     if type(IsInGroup) ~= "function" then return false end
     if LE_PARTY_CATEGORY_INSTANCE ~= nil then
         return IsInGroup(LE_PARTY_CATEGORY_INSTANCE)
     end
     return false
 end

 local function TryLFGTeleport(out)
     if type(LFGTeleport) == "function" then
         LFGTeleport(out and true or false)
         return true
     end
     return false
 end

 local function TryLeaveInstanceGroup()
     if C_PartyInfo and type(C_PartyInfo.LeaveParty) == "function" and LE_PARTY_CATEGORY_INSTANCE ~= nil then
         C_PartyInfo.LeaveParty(LE_PARTY_CATEGORY_INSTANCE)
         return true
     end
     return false
 end

-- Formats health values (e.g., 5500 -> 5.5K)
-- the number shown for a hidden (secret) value: formatted by the game
function RCPartyOrbs_ValueText(real)
    if AbbreviateNumbers then
        local ok, text = pcall(AbbreviateNumbers, real)
        if ok and text then return text end
    end
    return real -- FontString:SetText accepts a secret value
end

local function FormatHealth(val)
    if not val then return "0" end
    if val >= 1000000 then
        return string.format("%.1fM", val / 1000000)
    elseif val >= 1000 then
        return string.format("%.1fK", val / 1000)
    else
        return tostring(val)
    end
end

-- Helper to safely get class RGB
local function GetClassColor(unit)
    local _, class = UnitClass(unit)
    if class and CLASS_COLORS[class] then
        return unpack(CLASS_COLORS[class])
    end
    return 0.5, 0.5, 0.5 
end

-- Cache for party member class colors (persists even when out of range)
local partyClassColorCache = {}

-- Get class color with caching for party members
local function GetClassColorCached(unit)
    -- For player, always get fresh
    if unit == "player" then
        return GetClassColor(unit)
    end
    
    -- For party members, try to get fresh class info first
    local _, class = UnitClass(unit)
    if class and CLASS_COLORS[class] then
        -- Cache it for when they go out of range
        partyClassColorCache[unit] = {CLASS_COLORS[class][1], CLASS_COLORS[class][2], CLASS_COLORS[class][3]}
        return unpack(CLASS_COLORS[class])
    end
    
    -- If we can't get class info, use cached color
    if partyClassColorCache[unit] then
        return unpack(partyClassColorCache[unit])
    end
    
    -- Last resort fallback
    return 0.5, 0.5, 0.5
end

-- Get what the player can dispel (returns the dynamic list)
local function GetPlayerDispelTypes()
    -- If list is empty, try to update it
    if not next(playerDispelList) then
        UpdatePlayerDispels()
    end
    return playerDispelList
end

-- Get the dispel spell name for the player's class
local function GetPlayerDispelSpell()
    local _, playerClass = UnitClass("player")
    return CLASS_DISPEL_SPELLS[playerClass]
end

-- Get the purge/offensive dispel spell name for the player's class.
-- Returns nil if the spell is not currently available (e.g. Warlock without Felhunter).
local function GetPlayerPurgeSpell()
    local _, playerClass = UnitClass("player")
    local spell = CLASS_PURGE_SPELLS[playerClass]
    if not spell then return nil end

    -- Warlock's "Devour Magic" is a Felhunter pet ability — it only exists when a
    -- Felhunter (or Grimoire of Service: Felhunter) is the active pet.
    if playerClass == "WARLOCK" then
        if not UnitExists("pet") then return nil end
        -- UnitCreatureFamily returns the pet's type string (e.g. "Felhunter", "Imp", etc.)
        if UnitCreatureFamily("pet") ~= "Felhunter" then return nil end
    end

    return spell
end

-- Check if a unit (enemy) has a purgeable/stealable buff
-- Returns: true, r, g, b if purgeable buff found, nil otherwise
local function GetPurgeableBuff(unit)
    if not UnitExists(unit) then return nil end
    if not UnitCanAttack("player", unit) then return nil end  -- Only for enemies
    
    local purgeSpell = GetPlayerPurgeSpell()
    if not purgeSpell then return nil end  -- Player can't purge
    
    -- Scan all buffs on the unit
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, 
              nameplateShowPersonal, spellId = UnitBuff(unit, i)
        
        if not name then break end  -- No more buffs
        -- hidden in combat on Retail / WoW Forever: can't tell
        if RCPartyOrbs_Secret(isStealable) or RCPartyOrbs_Secret(debuffType) then return nil end
        
        -- Check if this buff is stealable/purgeable (Magic type buffs)
        if isStealable or debuffType == "Magic" then
            return true, PURGEABLE_BUFF_COLOR[1], PURGEABLE_BUFF_COLOR[2], PURGEABLE_BUFF_COLOR[3]
        end
    end
    
    return nil  -- No purgeable buffs found
end

-- Check if a unit has a dispellable debuff that the player can remove
-- Returns: debuffType, r, g, b or nil if no dispellable debuff
local function GetDispellableDebuff(unit)
    if not UnitExists(unit) then return nil end
    
    -- Check for test debuff mode first
    if testDebuffMode and testDebuffType then
        local color = DEBUFF_COLORS[testDebuffType]
        if color then
            return testDebuffType, color[1], color[2], color[3]
        end
    end
    
    local canDispel = GetPlayerDispelTypes()
    if not next(canDispel) then 
        if debugMode then
            print("|cFFFF0000RCPartyOrbs:|r GetDispellableDebuff - player can't dispel anything")
        end
        return nil 
    end
    
    -- Scan all debuffs on the unit
    -- Use UnitDebuff (or UnitAura with HARMFUL filter as fallback)
    local getDebuff = UnitDebuff or function(u, i) return UnitAura(u, i, "HARMFUL") end
    -- (UnitDebuff is the local above, rebuilt from C_UnitAuras on Retail / WoW Forever)
    
    for i = 1, 40 do
        local name, icon, count, debuffType, duration, expirationTime, source, isStealable, 
              nameplateShowPersonal, spellId = getDebuff(unit, i)
        
        if not name then break end  -- No more debuffs
        -- hidden in combat on Retail / WoW Forever: can't tell
        if RCPartyOrbs_Secret(name) or RCPartyOrbs_Secret(debuffType) then return nil end
        
        -- Debug: show all debuffs found
        if debugMode then
            print("|cFFFFFF00RCPartyOrbs:|r " .. unit .. " debuff " .. i .. ": " .. name .. " type=" .. tostring(debuffType) .. " canDispel=" .. tostring(canDispel[debuffType] or false))
        end
        
        -- Check if this debuff type can be dispelled by the player
        if debuffType and canDispel[debuffType] then
            local color = DEBUFF_COLORS[debuffType]
            if color then
                if debugMode then
                    print("|cFF00FF00RCPartyOrbs:|r Found dispellable " .. debuffType .. " on " .. unit .. ": " .. name)
                end
                return debuffType, color[1], color[2], color[3]
            end
        end
    end
    
    return nil  -- No dispellable debuffs found
end

-- Update orb color based on dispellable debuffs or purgeable buffs
local function UpdateOrbDebuffColor(frame)
    if not frame or not frame.unit then return end
    if not RCPartyOrbsDB.showDebuffColors then return end
    
    local unit = frame.unit
    local debuffType, r, g, b = nil, nil, nil, nil
    local isPurgeable = false
    
    -- Check for dispellable debuffs (friendly units)
    if UnitIsFriend("player", unit) or not UnitExists(unit) then
        debuffType, r, g, b = GetDispellableDebuff(unit)
    else
        -- Check for purgeable buffs (enemy units - target orb)
        isPurgeable, r, g, b = GetPurgeableBuff(unit)
    end
    
    if debuffType or isPurgeable then
        -- Play debuff alert sound if this is a NEW debuff (wasn't debuffed before)
        if not frame.hasDebuffColor and RCPartyOrbsDB.playDebuffSound ~= false then
            local soundKey = RCPartyOrbsDB.debuffSound or "default"
            local soundData = DEBUFF_SOUNDS[soundKey]
            
            if soundData and soundData.file then
                -- Play custom sound file
                PlaySoundFile(soundData.file, "Master")
            else
                -- Use WoW's ready check sound (bell/gong-like) as default
                PlaySound(SOUNDKIT.READY_CHECK, "Master")
            end
        end
        
        -- Store original color if not already stored
        if not originalOrbColors[unit] then
            originalOrbColors[unit] = {GetClassColor(unit)}
        end
        
        -- Make a lighter/brighter version of the debuff color for galaxies
        local lightR = math.min(1.0, r + 0.3)
        local lightG = math.min(1.0, g + 0.3)
        local lightB = math.min(1.0, b + 0.3)
        
        -- Apply debuff color to health orb filling
        if frame.healthOrb then
            if frame.healthOrb.filling then
                frame.healthOrb.filling:SetVertexColor(r, g, b, 1)
            end
            -- Apply lighter debuff color to galaxies
            if frame.healthOrb.galaxy1 and frame.healthOrb.galaxy1.texture then 
                frame.healthOrb.galaxy1.texture:SetVertexColor(lightR, lightG, lightB, 1) 
            end
            if frame.healthOrb.galaxy2 and frame.healthOrb.galaxy2.texture then 
                frame.healthOrb.galaxy2.texture:SetVertexColor(lightR, lightG, lightB, 1) 
            end
            if frame.healthOrb.galaxy3 and frame.healthOrb.galaxy3.texture then 
                frame.healthOrb.galaxy3.texture:SetVertexColor(lightR, lightG, lightB, 1) 
            end
        end
        
        -- Tint the mana orb to the debuff color
        if frame.manaOrb and frame.manaOrb.filling then
            frame.manaOrb.filling:SetVertexColor(r * 0.8, g * 0.8, b * 0.8, 1)
        end
        
        frame.hasDebuffColor = true
        frame.hasPurgeableBuff = isPurgeable
    else
        -- Restore original color if we had a debuff color applied
        if frame.hasDebuffColor then
            local origColor = originalOrbColors[unit]
            if origColor then
                local cr, cg, cb = origColor[1], origColor[2], origColor[3]
                -- Restore health orb filling to class color
                if frame.healthOrb then
                    if frame.healthOrb.filling then
                        frame.healthOrb.filling:SetVertexColor(cr, cg, cb, 1)
                    end
                    -- Restore galaxy colors to class color
                    if frame.healthOrb.galaxy1 and frame.healthOrb.galaxy1.texture then 
                        frame.healthOrb.galaxy1.texture:SetVertexColor(cr, cg, cb, 1) 
                    end
                    if frame.healthOrb.galaxy2 and frame.healthOrb.galaxy2.texture then 
                        frame.healthOrb.galaxy2.texture:SetVertexColor(cr, cg, cb, 1) 
                    end
                    if frame.healthOrb.galaxy3 and frame.healthOrb.galaxy3.texture then 
                        frame.healthOrb.galaxy3.texture:SetVertexColor(cr, cg, cb, 1) 
                    end
                end
                -- Restore mana orb to brighter blue
                if frame.manaOrb and frame.manaOrb.filling then
                    frame.manaOrb.filling:SetVertexColor(0.2, 0.7, 1.0, 1)
                end
            end
            frame.hasDebuffColor = false
            frame.hasPurgeableBuff = false
            originalOrbColors[unit] = nil
        end
    end
end

-- Global flag to prevent reposition loops
local isRepositioning = false
local isDragging = false

-- Calculates position and anchor for orbs (now uses PositionOrbs from section 7)
function RCPartyOrbs_RepositionOrbs()
    if isDragging then return end
    isRepositioning = true
    
    -- Call the new positioning function if orbFrames exists
    if orbFrames and PositionOrbs then
        PositionOrbs()
    end
    
    isRepositioning = false
end

-----------------------------------------------------------
-- 3. VISIBILITY LOGIC (Party vs Raid or Toggle)
-----------------------------------------------------------

-- Track if we need to update visibility after combat
local pendingVisibilityUpdate = false

function RCPartyOrbs_UpdateVisibility()
    local debug = RCPartyOrbsDB and RCPartyOrbsDB.debugMode
    
    -- Don't modify secure frames during combat
    if InCombatLockdown() then
        pendingVisibilityUpdate = true
        if debug then print("UpdateVisibility: In combat, queued for later") end
        return
    end
    
    if debug then print("UpdateVisibility called, showPlayerOrbs=" .. tostring(RCPartyOrbsDB.showPlayerOrbs)) end
    
    -- In test mode, show all orbs (respecting individual visibility settings)
    if testMode then
        if debug then print("  -> Test mode active, showing based on visibility settings") end
        -- Player orb
        if orbFrames and orbFrames[1] then
            if RCPartyOrbsDB.showPlayerOrb ~= false then
                orbFrames[1]:Show()
            else
                orbFrames[1]:Hide()
            end
        end
        -- Party orbs 1-4
        local partyOrbSettings = {
            RCPartyOrbsDB.showParty1Orb,
            RCPartyOrbsDB.showParty2Orb,
            RCPartyOrbsDB.showParty3Orb,
            RCPartyOrbsDB.showParty4Orb
        }
        for i = 2, 5 do
            if orbFrames and orbFrames[i] then
                if partyOrbSettings[i-1] ~= false then
                    orbFrames[i]:Show()
                else
                    orbFrames[i]:Hide()
                end
            end
        end
        -- Target orb
        if orbFrames and orbFrames[6] then
            if RCPartyOrbsDB.showTargetOrb ~= false then
                orbFrames[6]:Show()
            else
                orbFrames[6]:Hide()
            end
        end
        -- Party target orbs
        local partyTargetSettings = {
            RCPartyOrbsDB.showParty1Target,
            RCPartyOrbsDB.showParty2Target,
            RCPartyOrbsDB.showParty3Target,
            RCPartyOrbsDB.showParty4Target
        }
        local showPartyTargets = RCPartyOrbsDB.showPartyTargets ~= false
        for i = 7, 10 do
            if orbFrames and orbFrames[i] then
                local partyNum = i - 6
                if showPartyTargets and partyTargetSettings[partyNum] ~= false then
                    orbFrames[i]:Show()
                else
                    orbFrames[i]:Hide()
                end
            end
        end
        RCPartyOrbs_HideBlizzardFrames()
        return
    end
    
    if not RCPartyOrbsDB or not RCPartyOrbsDB.enabled then
        if debug then print("  -> Addon disabled, hiding all") end
        for i = 1, 10 do
            if orbFrames and orbFrames[i] then
                orbFrames[i]:Hide()
            end
        end
        RCPartyOrbs_ShowBlizzardFrames()
        return
    end
    
    -- Check if orbs are toggled off via Hide Orbs button
    if RCPartyOrbsDB.showPlayerOrbs == false then
        if debug then print("  -> showPlayerOrbs=false, hiding all orbs") end
        -- Hide ALL orbs
        for i = 1, 10 do
            if orbFrames and orbFrames[i] then
                orbFrames[i]:Hide()
            end
        end
        -- Show Blizzard frames
        RCPartyOrbs_ShowBlizzardFrames()
        return
    end
    
    if debug then print("  -> Normal mode, showing based on units and visibility settings") end
    
    -- In raid, hide ALL orbs (let raid frames handle everything)
    if IsInRaid() then
        if debug then print("  -> In raid, hiding ALL orbs") end
        for i = 1, 10 do
            if orbFrames and orbFrames[i] then
                orbFrames[i]:Hide()
            end
        end
        RCPartyOrbs_ShowBlizzardFrames()
        return
    end
    
    -- In party or solo, show orbs based on individual visibility settings
    if debug then print("  -> Normal mode, showing based on units and visibility settings") end
    
    -- Player orb - show if setting enabled
    if orbFrames and orbFrames[1] then
        if RCPartyOrbsDB.showPlayerOrb ~= false then
            orbFrames[1]:Show()
            if debug then print("  -> Showing player orb") end
        else
            orbFrames[1]:Hide()
        end
    end
    
    -- Party orbs - show if party member exists AND setting enabled
    local partyOrbSettings = {
        RCPartyOrbsDB.showParty1Orb,
        RCPartyOrbsDB.showParty2Orb,
        RCPartyOrbsDB.showParty3Orb,
        RCPartyOrbsDB.showParty4Orb
    }
    for i = 2, 5 do
        if orbFrames and orbFrames[i] then
            local partyNum = i - 1
            if partyOrbSettings[partyNum] ~= false and UnitExists("party" .. partyNum) then
                orbFrames[i]:Show()
                if debug then print("  -> Showing party" .. partyNum .. " orb") end
            else
                orbFrames[i]:Hide()
            end
        end
    end
    
    -- Target orb - show if target exists AND setting enabled
    if orbFrames and orbFrames[6] then
        if RCPartyOrbsDB.showTargetOrb ~= false and UnitExists("target") then
            orbFrames[6]:Show()
            if debug then print("  -> Showing target orb") end
        else
            orbFrames[6]:Hide()
        end
    end
    
    -- Party target orbs (7-10) - show if:
    -- 1. Master toggle (showPartyTargets) is enabled
    -- 2. Individual toggle is enabled
    -- 3. Party member exists
    -- 4. Party member has a target
    local showPartyTargets = RCPartyOrbsDB.showPartyTargets ~= false
    local partyTargetSettings = {
        RCPartyOrbsDB.showParty1Target,
        RCPartyOrbsDB.showParty2Target,
        RCPartyOrbsDB.showParty3Target,
        RCPartyOrbsDB.showParty4Target
    }
    for i = 7, 10 do
        if orbFrames and orbFrames[i] then
            local partyNum = i - 6
            local showThis = showPartyTargets 
                and partyTargetSettings[partyNum] ~= false
                and UnitExists("party" .. partyNum) 
                and UnitExists("party" .. partyNum .. "target")
            if showThis then
                orbFrames[i]:Show()
                if debug then print("  -> Showing party" .. partyNum .. "target orb") end
            else
                orbFrames[i]:Hide()
            end
        end
    end
    
    -- Hide Blizzard frames
    RCPartyOrbs_HideBlizzardFrames()
end

function RCPartyOrbs_HideBlizzardFrames()
    -- Only hide Blizzard PARTY frames - leave player/target alone for ElvUI users
    for i = 1, 4 do 
        local pFrame = _G["PartyMemberFrame"..i]
        if pFrame then 
            pFrame:Hide()
            pFrame:UnregisterAllEvents()
            -- Prevent the frame from showing again
            pFrame:SetScript("OnShow", function(self) self:Hide() end)
            -- Also disable the mana bar events to prevent the UnitFrameManaCostPredictionBars_Update error
            if pFrame.manabar then
                pFrame.manabar:UnregisterAllEvents()
            end
            if pFrame.ManaBar then
                pFrame.ManaBar:UnregisterAllEvents()
            end
            if pFrame.healthbar then
                pFrame.healthbar:UnregisterAllEvents()
            end
            if pFrame.HealthBar then
                pFrame.HealthBar:UnregisterAllEvents()
            end
        end
        -- Also hide pet frames
        local petFrame = _G["PartyMemberFrame"..i.."PetFrame"]
        if petFrame then
            petFrame:Hide()
            petFrame:UnregisterAllEvents()
            petFrame:SetScript("OnShow", function(self) self:Hide() end)
        end
    end
    
    -- Also hide the compact party frame if it exists (MoP)
    if CompactPartyFrame then
        pcall(function()
            CompactPartyFrame:Hide()
            CompactPartyFrame:UnregisterAllEvents()
            CompactPartyFrame:SetScript("OnShow", function(self) self:Hide() end)
        end)
    end
    
    -- Hide the party frame container if it exists
    if PartyFrame then
        pcall(function()
            PartyFrame:Hide()
            PartyFrame:UnregisterAllEvents()
            PartyFrame:SetScript("OnShow", function(self) self:Hide() end)
        end)
    end
    
    -- Hide all supported unit frame addon PARTY frames
    RCPartyOrbs_HideAllUnitFrameAddons()
end

-- ============================================
-- UNIT FRAME ADDON COMPATIBILITY
-- Supports: ElvUI, SUF, Pitbull, Z-Perl, Luna
-- ============================================

-- Generic helper to safely hide a frame
local function SafeHideFrame(frame)
    if frame and not InCombatLockdown() then
        frame.rcPartyOrbsHidden = true
        frame:Hide()
    end
end

-- Generic helper to safely show a frame
local function SafeShowFrame(frame, condition)
    if frame and not InCombatLockdown() then
        frame.rcPartyOrbsHidden = nil
        if condition == nil or condition then
            frame:Show()
        end
    end
end

-- ============================================
-- ELVUI
-- ONLY hides party frames - nothing else!
-- ============================================

-- Helper to set alpha on a frame and children
local function SetFrameAlphaRecursive(frame, alpha)
    if not frame then return end
    frame:SetAlpha(alpha)
    for _, child in ipairs({frame:GetChildren()}) do
        child:SetAlpha(alpha)
    end
end

function RCPartyOrbs_HideElvUIFrames()
    if not ElvUI then return end
    if InCombatLockdown() then return end
    
    -- ONLY hide party frames - nothing else!
    local frames = {
        _G["ElvUF_Party"],
        _G["ElvUF_PartyGroup1"],
    }
    
    for i = 1, 5 do
        table.insert(frames, _G["ElvUF_PartyGroup1UnitButton" .. i])
    end
    
    for _, frame in ipairs(frames) do
        if frame then
            frame.rcPartyOrbsHidden = true
            SetFrameAlphaRecursive(frame, 0)
            frame:EnableMouse(false)
        end
    end
end

function RCPartyOrbs_ShowElvUIFrames()
    if not ElvUI then return end
    if InCombatLockdown() then return end
    
    -- Only restore party frames
    local frames = {
        _G["ElvUF_Party"],
        _G["ElvUF_PartyGroup1"],
    }
    
    for i = 1, 5 do
        table.insert(frames, _G["ElvUF_PartyGroup1UnitButton" .. i])
    end
    
    for _, frame in ipairs(frames) do
        if frame then
            frame.rcPartyOrbsHidden = nil
            SetFrameAlphaRecursive(frame, 1)
            frame:EnableMouse(true)
        end
    end
end

-- ============================================
-- SHADOWED UNIT FRAMES (SUF)
-- ============================================
function RCPartyOrbs_HideSUFFrames()
    if not ShadowUF then return end
    if InCombatLockdown() then return end
    
    SafeHideFrame(_G["SUFUnitplayer"])
    SafeHideFrame(_G["SUFUnittarget"])
    SafeHideFrame(_G["SUFUnittargettarget"])
    SafeHideFrame(_G["SUFHeaderpartyUnitButton1"])
    SafeHideFrame(_G["SUFHeaderpartyUnitButton2"])
    SafeHideFrame(_G["SUFHeaderpartyUnitButton3"])
    SafeHideFrame(_G["SUFHeaderpartyUnitButton4"])
    SafeHideFrame(_G["SUFHeaderpartyUnitButton5"])
    
    -- Also try alternate naming
    for i = 1, 5 do
        SafeHideFrame(_G["SUFUnitparty" .. i])
    end
end

function RCPartyOrbs_ShowSUFFrames()
    if not ShadowUF then return end
    if InCombatLockdown() then return end
    
    SafeShowFrame(_G["SUFUnitplayer"], true)
    SafeShowFrame(_G["SUFUnittarget"], UnitExists("target"))
    SafeShowFrame(_G["SUFUnittargettarget"], UnitExists("targettarget"))
    
    for i = 1, 5 do
        SafeShowFrame(_G["SUFHeaderpartyUnitButton" .. i], UnitExists("party" .. i))
        SafeShowFrame(_G["SUFUnitparty" .. i], UnitExists("party" .. i))
    end
end

-- ============================================
-- PITBULL4
-- ============================================
function RCPartyOrbs_HidePitbullFrames()
    if not PitBull4 then return end
    if InCombatLockdown() then return end
    
    -- Pitbull uses dynamic frame names based on user config
    -- Common patterns: PitBull4_Frames_Player, PitBull4_Frames_Target, etc.
    SafeHideFrame(_G["PitBull4_Frames_Player"])
    SafeHideFrame(_G["PitBull4_Frames_Target"])
    SafeHideFrame(_G["PitBull4_Frames_Target's target"])
    SafeHideFrame(_G["PitBull4_Frames_TargetTarget"])
    
    -- Party frames
    for i = 1, 4 do
        SafeHideFrame(_G["PitBull4_Frames_Party" .. i])
        SafeHideFrame(_G["PitBull4_Frames_Party " .. i])
    end
    
    -- Also check for group headers
    SafeHideFrame(_G["PitBull4_Groups_Party"])
end

function RCPartyOrbs_ShowPitbullFrames()
    if not PitBull4 then return end
    if InCombatLockdown() then return end
    
    SafeShowFrame(_G["PitBull4_Frames_Player"], true)
    SafeShowFrame(_G["PitBull4_Frames_Target"], UnitExists("target"))
    SafeShowFrame(_G["PitBull4_Frames_Target's target"], UnitExists("targettarget"))
    SafeShowFrame(_G["PitBull4_Frames_TargetTarget"], UnitExists("targettarget"))
    
    for i = 1, 4 do
        SafeShowFrame(_G["PitBull4_Frames_Party" .. i], UnitExists("party" .. i))
        SafeShowFrame(_G["PitBull4_Frames_Party " .. i], UnitExists("party" .. i))
    end
    
    SafeShowFrame(_G["PitBull4_Groups_Party"], true)
end

-- ============================================
-- Z-PERL / X-PERL
-- ============================================
function RCPartyOrbs_HideZPerlFrames()
    -- Check for both Z-Perl and X-Perl
    if not (XPerl or ZPerl or _G["XPerl_Player"]) then return end
    if InCombatLockdown() then return end
    
    SafeHideFrame(_G["XPerl_Player"])
    SafeHideFrame(_G["XPerl_Target"])
    SafeHideFrame(_G["XPerl_TargetTarget"])
    SafeHideFrame(_G["XPerl_Player_Pet"])
    
    for i = 1, 4 do
        SafeHideFrame(_G["XPerl_party" .. i])
    end
    
    -- Z-Perl naming
    SafeHideFrame(_G["ZPerl_Player"])
    SafeHideFrame(_G["ZPerl_Target"])
    SafeHideFrame(_G["ZPerl_TargetTarget"])
    
    for i = 1, 4 do
        SafeHideFrame(_G["ZPerl_party" .. i])
    end
end

function RCPartyOrbs_ShowZPerlFrames()
    if not (XPerl or ZPerl or _G["XPerl_Player"]) then return end
    if InCombatLockdown() then return end
    
    SafeShowFrame(_G["XPerl_Player"], true)
    SafeShowFrame(_G["XPerl_Target"], UnitExists("target"))
    SafeShowFrame(_G["XPerl_TargetTarget"], UnitExists("targettarget"))
    SafeShowFrame(_G["XPerl_Player_Pet"], UnitExists("pet"))
    
    for i = 1, 4 do
        SafeShowFrame(_G["XPerl_party" .. i], UnitExists("party" .. i))
    end
    
    SafeShowFrame(_G["ZPerl_Player"], true)
    SafeShowFrame(_G["ZPerl_Target"], UnitExists("target"))
    SafeShowFrame(_G["ZPerl_TargetTarget"], UnitExists("targettarget"))
    
    for i = 1, 4 do
        SafeShowFrame(_G["ZPerl_party" .. i], UnitExists("party" .. i))
    end
end

-- ============================================
-- LUNA UNIT FRAMES
-- ============================================
function RCPartyOrbs_HideLunaFrames()
    if not LunaUnitFrames then return end
    if InCombatLockdown() then return end
    
    SafeHideFrame(_G["LunaPlayerFrame"])
    SafeHideFrame(_G["LunaTargetFrame"])
    SafeHideFrame(_G["LunaTargetTargetFrame"])
    SafeHideFrame(_G["LunaPartyFrame"])
    
    for i = 1, 4 do
        SafeHideFrame(_G["LunaPartyFrame" .. i])
    end
end

function RCPartyOrbs_ShowLunaFrames()
    if not LunaUnitFrames then return end
    if InCombatLockdown() then return end
    
    SafeShowFrame(_G["LunaPlayerFrame"], true)
    SafeShowFrame(_G["LunaTargetFrame"], UnitExists("target"))
    SafeShowFrame(_G["LunaTargetTargetFrame"], UnitExists("targettarget"))
    SafeShowFrame(_G["LunaPartyFrame"], true)
    
    for i = 1, 4 do
        SafeShowFrame(_G["LunaPartyFrame" .. i], UnitExists("party" .. i))
    end
end

-- ============================================
-- MASTER FUNCTIONS - Hide/Show ALL supported addons
-- ============================================
function RCPartyOrbs_HideAllUnitFrameAddons()
    RCPartyOrbs_HideElvUIFrames()
    RCPartyOrbs_HideSUFFrames()
    RCPartyOrbs_HidePitbullFrames()
    RCPartyOrbs_HideZPerlFrames()
    RCPartyOrbs_HideLunaFrames()
end

function RCPartyOrbs_ShowAllUnitFrameAddons()
    RCPartyOrbs_ShowElvUIFrames()
    RCPartyOrbs_ShowSUFFrames()
    RCPartyOrbs_ShowPitbullFrames()
    RCPartyOrbs_ShowZPerlFrames()
    RCPartyOrbs_ShowLunaFrames()
end

-- Force restore all unit frame addons (emergency recovery)
function RCPartyOrbs_ForceRestoreAllUnitFrames()
    if InCombatLockdown() then
        print("|cFFFF0000RCPartyOrbs:|r Cannot restore frames during combat. Try again after combat.")
        return
    end
    
    print("|cFF00FF00RCPartyOrbs:|r Force restoring all unit frame addons...")
    
    -- Restore ElvUI
    if ElvUI then
        RCPartyOrbs_ForceRestoreElvUI()
    end
    
    -- Restore SUF
    RCPartyOrbs_ShowSUFFrames()
    
    -- Restore Pitbull
    RCPartyOrbs_ShowPitbullFrames()
    
    -- Restore Z-Perl/X-Perl
    RCPartyOrbs_ShowZPerlFrames()
    
    -- Restore Luna
    RCPartyOrbs_ShowLunaFrames()
    
    print("|cFF00FF00RCPartyOrbs:|r All unit frames restored. /reload if issues persist.")
end

-- Force restore ElvUI party frames (emergency recovery)
function RCPartyOrbs_ForceRestoreElvUI()
    if not ElvUI then 
        print("|cFFFF0000RCPartyOrbs:|r ElvUI not detected")
        return 
    end
    
    if InCombatLockdown() then
        print("|cFFFF0000RCPartyOrbs:|r Cannot restore frames during combat. Try again after combat.")
        return
    end
    
    print("|cFF00FF00RCPartyOrbs:|r Force restoring ElvUI party frames...")
    
    -- Only restore party frames
    local frames = {
        _G["ElvUF_Party"],
        _G["ElvUF_PartyGroup1"],
    }
    
    for i = 1, 5 do
        table.insert(frames, _G["ElvUF_PartyGroup1UnitButton" .. i])
    end
    
    for _, frame in ipairs(frames) do
        if frame then
            frame.rcPartyOrbsHidden = nil
            SetFrameAlphaRecursive(frame, 1)
            frame:EnableMouse(true)
        end
    end
    
    print("|cFF00FF00RCPartyOrbs:|r ElvUI party frames restored.")
end

-- NOTE: We previously had a hook system here to prevent ElvUI frames from
-- re-showing, but it was causing cascade issues with ElvUI's SecureStateDriver
-- that triggered errors on raid frames. The simple hide/show approach with
-- combat lockdown checks is safer and more compatible.

function RCPartyOrbs_ShowBlizzardFrames()
    -- Only restore Blizzard PARTY frames
    for i = 1, 4 do 
        local pFrame = _G["PartyMemberFrame"..i]
        if pFrame then 
            pFrame:SetAlpha(1)
            pFrame:RegisterAllEvents()
            if UnitExists("party"..i) then
                pFrame:Show()
            else
                pFrame:Hide()
            end
        end
    end
    
    -- Show all supported unit frame addon PARTY frames
    RCPartyOrbs_ShowAllUnitFrameAddons()
end

-----------------------------------------------------------
-- 4. SWIRL & ANIMATION LOGIC
-----------------------------------------------------------

-- Refreshes the galaxy/swirl textures for an orb (RCDiabloOrbs style)
function UpdateOrbSwirls(orb)
    -- Skip swirls for target orb
    if orb.unit == "target" then return end
    
    local swirlTextures = SWIRL_SETS[currentSwirlSet] or SWIRL_SETS["bubbles"]
    
    -- Update existing galaxy textures on the health orb
    if orb.healthOrb then
        if orb.healthOrb.galaxy1 and orb.healthOrb.galaxy1.texture then
            orb.healthOrb.galaxy1.texture:SetTexture(swirlTextures[1])
        end
        if orb.healthOrb.galaxy2 and orb.healthOrb.galaxy2.texture then
            orb.healthOrb.galaxy2.texture:SetTexture(swirlTextures[2])
        end
        if orb.healthOrb.galaxy3 and orb.healthOrb.galaxy3.texture then
            orb.healthOrb.galaxy3.texture:SetTexture(swirlTextures[3])
        end
    end
end

-----------------------------------------------------------
-- 5. CUSTOM MENU LOGIC
-----------------------------------------------------------

-- Create a custom dropdown function that adds dungeon options to the standard menu
local function CustomUnitMenu(self, unit)
    Compat.ShowUnitMenu(self, unit)
end

-- Creates and sets up the unit dropdown menu
local function SetupUnitMenu(frame, unit)
    -- Skip if this is a non-unit frame
    if not unit then return end
    
    frame:RegisterForClicks("AnyDown")
    frame:SetAttribute("*type2", "menu")
    
    -- Use our custom menu function
    frame.menu = function(self)
CustomUnitMenu(self, frame.unit)
    end
    
    SecureUnitButton_OnLoad(frame, unit, frame.menu)
end

-----------------------------------------------------------
-- 6. ORB FRAME CONSTRUCTION
-----------------------------------------------------------

local images = "Interface\\AddOns\\RCPartyOrbs\\images\\"
local fonts = "Interface\\AddOns\\RCPartyOrbs\\fonts\\"

-- Creates a rotating galaxy/swirl texture (RCDiabloOrbs style)
local function CreateGalaxy(orb, file, duration, size, x, y)
    local galaxy = CreateFrame("Frame", nil, orb)
    galaxy:SetHeight(size)
    galaxy:SetWidth(size)
    galaxy:SetPoint("CENTER", x, y)
    galaxy:SetFrameLevel(4)
    
    local galTex = galaxy:CreateTexture()
    galTex:SetAllPoints(galaxy)
    galTex:SetTexture(file)
    galTex:SetBlendMode("ADD")
    galTex:SetAlpha(0.6)
    galaxy.texture = galTex
    
    local animGroup = galaxy:CreateAnimationGroup()
    galaxy.animGroup = animGroup
    
    local anim1 = animGroup:CreateAnimation("Rotation")
    anim1:SetDegrees(360)
    anim1:SetDuration(duration)
    galaxy.animGroup.anim1 = anim1
    
    animGroup:Play()
    animGroup:SetLooping("REPEAT")
    
    return galaxy
end

-- Create a single orb (health OR mana) - RCDiabloOrbs style
local function CreateSingleOrb(parent, name, size, fillTexture, galaxyTextures, skipGalaxies)
    local orb = CreateFrame("Frame", name, parent)
    
    orb:SetHeight(size)
    orb:SetWidth(size)
    orb:SetFrameStrata("LOW")
    
    -- Create background gloss (top layer)
    orb.bg = orb:CreateTexture(nil, "OVERLAY")
    orb.bg:SetTexture(images .. "orb_gloss3.tga")
    orb.bg:SetAllPoints(orb)
    
    -- Create the fill texture
    orb.filling = orb:CreateTexture(nil, "BACKGROUND")
    orb.filling:SetTexture(images .. fillTexture)
    orb.filling:SetPoint("BOTTOMLEFT", 3, 3)
    orb.filling:SetWidth(size - 6)
    orb.filling:SetHeight(size - 6)
    orb.filling:SetAlpha(1)
    
    -- Create gloss overlay holder (RCDiabloOrbs style)
    local orbGlossHolder = CreateFrame("Frame", nil, orb)
    orbGlossHolder:SetAllPoints(orb)
    orbGlossHolder:SetFrameStrata("BACKGROUND")
    local orbGlossOverlay = orbGlossHolder:CreateTexture(nil, "BACKGROUND")
    orbGlossOverlay:SetTexture(images .. "orb_gloss3.tga")
    orbGlossOverlay:SetAllPoints(orbGlossHolder)
    
    -- Create rotating galaxy swirls (only for health orb, not mana)
    if not skipGalaxies and galaxyTextures then
        local newRand = math.random(20, 50)
        orb.galaxy1 = CreateGalaxy(orb, galaxyTextures[1], newRand, size - 5, 0, 0)
        newRand = math.random(30, 70)
        orb.galaxy2 = CreateGalaxy(orb, galaxyTextures[2], newRand, size - 5, 0, 0)
        newRand = math.random(18, 27)
        orb.galaxy3 = CreateGalaxy(orb, galaxyTextures[3], newRand, size - 5, 0, 0)
    end
    
    orb:Show()
    return orb
end

-- Create a stacked orb unit frame (mana orb larger, health orb centered on top)
local function CreateStackedOrbFrame(unit, index)
    local baseSize = RCPartyOrbsDB.orbSize or ORB_SIZE
    
    -- Target orb and party target orbs use their own scale setting
    if unit == "target" or (unit and unit:match("party%dtarget")) then
        local targetScale = RCPartyOrbsDB.targetOrbScale or 75
        baseSize = baseSize * (targetScale / 100)
    end
    
    local manaSize = baseSize * 1.3  -- Mana orb is 30% BIGGER than health
    local healthSize = baseSize  -- Health orb is base size
    
    local swirlTextures = SWIRL_SETS[currentSwirlSet] or SWIRL_SETS["bubbles"]
    
    -- Create main container (clickable for unit interaction)
    local container = CreateFrame("Button", "RCPartyOrbFrame"..index, UIParent, "SecureUnitButtonTemplate")
    container:SetSize(manaSize, manaSize)  -- Container is size of mana orb
    container:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    container:SetFrameStrata("BACKGROUND")
    -- Party member orbs (player, party1-4) must have HIGHER frame level than target orbs
    -- so they win clicks if any overlap occurs (target orbs sit behind party orbs)
    local isTargetOrb = (unit == "target") or (unit and unit:match("party%dtarget"))
    container:SetFrameLevel(isTargetOrb and 2 or 10)
    -- Shrink the clickable hit rect inward so adjacent orbs have a clear dead zone.
    -- For party/player orbs: extra inset on the bottom edge so the target orb below
    -- (in horizontal layout) doesn't compete with the party orb for clicks.
    -- For target orbs: extra inset on top to stay clear of the party orb above.
    -- Values: left, right, top, bottom (positive = shrink inward).
    if isTargetOrb then
        container:SetHitRectInsets(4, 4, 10, 4)
    else
        container:SetHitRectInsets(4, 4, 4, 10)
    end
    container:SetAttribute("unit", unit)
    container:RegisterForClicks("AnyDown")
    container.unit = unit
    SecureUnitButton_OnLoad(container, unit)
    
    -- Get player's spells
    local dispelSpell = GetPlayerDispelSpell()
    local purgeSpell = GetPlayerPurgeSpell()
    local combatRez = GetPlayerRezSpell()
    
    -- Store spells for reference
    container.dispelSpell = dispelSpell
    container.purgeSpell = purgeSpell
    container.combatRez = combatRez
    
    -- Build the macro for dispel/rez using @unit syntax (like Decursive does)
    -- Format: /cast [@unit, help, nodead] Dispel; [@unit, help, dead, combat] BattleRez; [@unit, harm] Purge
    -- This explicitly targets the frame's unit regardless of current target
    local macroParts = {}
    
    -- Add dispel for living friendly targets
    if dispelSpell then
        table.insert(macroParts, string.format("[@%s,help,nodead] %s", unit, dispelSpell))
    end
    
    -- Add battle rez for dead friendly targets (combat only)
    if combatRez then
        table.insert(macroParts, string.format("[@%s,help,dead,combat] %s", unit, combatRez))
    end
    
    -- Add purge for enemy targets (target orb)
    if purgeSpell then
        table.insert(macroParts, string.format("[@%s,harm,nodead] %s", unit, purgeSpell))
    end
    
    -- Left-click always targets the unit
    container:SetAttribute("type1", "target")
    
    -- Set up ALL modifier attributes - the active one casts, others just target
    -- This allows changing the modifier without requiring /reload
    local macroText = ""
    if #macroParts > 0 then
        macroText = "/cast " .. table.concat(macroParts, "; ")
    end
    
    local currentMod = RCPartyOrbsDB.clickModifier or "shift"
    
    -- Set each modifier - active one gets macro if we have dispel spells, 
    -- otherwise let the click pass through for normal spell casting
    for _, mod in ipairs({"shift", "alt", "ctrl"}) do
        if mod == currentMod and macroText ~= "" then
            container:SetAttribute(mod .. "-type1", "macro")
            container:SetAttribute(mod .. "-macrotext1", macroText)
        else
            -- Clear the attribute so shift-click passes through for spell casting
            container:SetAttribute(mod .. "-type1", nil)
            container:SetAttribute(mod .. "-macrotext1", nil)
        end
    end
    
    -- Store the macro text for later updates
    container.castMacroText = macroText
    
    if debugMode and macroText ~= "" then
        print("|cFF00FF00RCPartyOrbs:|r Macro for " .. unit .. " (" .. currentMod .. "+click): " .. macroText)
    end
    
    -- Right-click opens unit menu
    container:SetAttribute("type2", "togglemenu")
    
    -- Make container movable (when frames are unlocked)
    container:SetMovable(true)
    container:SetClampedToScreen(true)  -- Prevent dragging off screen
    container:EnableMouse(true)
    -- Only register for drag when frames are unlocked (avoids click/drag race on SecureUnitButtonTemplate)
    container:RegisterForDrag("LeftButton")
    container:SetScript("OnDragStart", function(self)
        if RCPartyOrbsDB.framesLocked or InCombatLockdown() then
            return
        end
        
        -- Save all positions before moving for undo
        if not RCPartyOrbsDB.lastOrbPositions then RCPartyOrbsDB.lastOrbPositions = {} end
        for i = 1, 6 do
            if orbFrames and orbFrames[i] then
                local pt, rel, relPt, x, y = orbFrames[i]:GetPoint()
                if pt then
                    RCPartyOrbsDB.lastOrbPositions[orbFrames[i].unit] = {
                        point = pt,
                        relativeTo = rel and rel:GetName() or "UIParent",
                        relativePoint = relPt,
                        x = x,
                        y = y
                    }
                end
            end
        end
        
        if IsShiftKeyDown() then
            -- Shift+drag: move individual orb
            self:StartMoving()
            self.movingIndividual = true
        else
            -- Normal drag: move all orbs together as a group
            -- First, calculate offsets of all orbs relative to this orb
            local myX, myY = self:GetCenter()
            if not myX or not myY then return end
            
            self.groupOffsets = {}
            for i = 1, 6 do
                if orbFrames and orbFrames[i] then
                    local cx, cy = orbFrames[i]:GetCenter()
                    if cx and cy then
                        self.groupOffsets[i] = {x = cx - myX, y = cy - myY}
                    end
                end
            end
            
            -- Start moving this orb (we'll update others in OnUpdate)
            self:StartMoving()
            self.movingGroup = true
            self.groupLeader = self  -- Track which orb is being dragged
            
            -- Set up OnUpdate to move all orbs together
            self:SetScript("OnUpdate", function(frame)
                if frame.movingGroup and frame.groupOffsets then
                    local cx, cy = frame:GetCenter()
                    if cx and cy then
                        local sw = UIParent:GetWidth()
                        local sh = UIParent:GetHeight()
                        for i = 1, 6 do
                            if orbFrames and orbFrames[i] and orbFrames[i] ~= frame and frame.groupOffsets[i] then
                                local fw = orbFrames[i]:GetWidth()  or 0
                                local fh = orbFrames[i]:GetHeight() or 0
                                local nx = cx + frame.groupOffsets[i].x
                                local ny = cy + frame.groupOffsets[i].y
                                -- Clamp so the orb centre stays within half-width/height of the screen edge
                                nx = math.max(fw * 0.5, math.min(sw - fw * 0.5, nx))
                                ny = math.max(fh * 0.5, math.min(sh - fh * 0.5, ny))
                                orbFrames[i]:ClearAllPoints()
                                orbFrames[i]:SetPoint("CENTER", UIParent, "BOTTOMLEFT", nx, ny)
                            end
                        end
                    end
                end
            end)
        end
    end)
    container:SetScript("OnDragStop", function(self)
        if self.movingIndividual then
            self:StopMovingOrSizing()
            self.movingIndividual = false
            -- Only save position for player orb - all others use orientation-based positioning
            if unit == "player" then
                local point, relativeTo, relativePoint, xOfs, yOfs = self:GetPoint()
                if not RCPartyOrbsDB.orbPositions then RCPartyOrbsDB.orbPositions = {} end
                RCPartyOrbsDB.orbPositions[unit] = {
                    point = point,
                    relativeTo = relativeTo and relativeTo:GetName() or "UIParent",
                    relativePoint = relativePoint,
                    x = xOfs,
                    y = yOfs
                }
            end
            -- Re-position all orbs based on player position and orientation
            PositionOrbs()
        elseif self.movingGroup then
            self:StopMovingOrSizing()
            self:SetScript("OnUpdate", nil)  -- Remove OnUpdate
            self.movingGroup = false
            self.groupOffsets = nil
            
            -- Only save player orb position
            if not RCPartyOrbsDB.orbPositions then RCPartyOrbsDB.orbPositions = {} end
            if orbFrames[1] then
                local point, relativeTo, relativePoint, xOfs, yOfs = orbFrames[1]:GetPoint()
                RCPartyOrbsDB.orbPositions["player"] = {
                    point = point,
                    relativeTo = relativeTo and relativeTo:GetName() or "UIParent",
                    relativePoint = relativePoint,
                    x = xOfs,
                    y = yOfs
                }
            end
            -- Re-position all orbs based on player position and orientation
            PositionOrbs()
        end
    end)
    
    -- Tooltip
    container:SetScript("OnEnter", function()
        GameTooltip_SetDefaultAnchor(GameTooltip, UIParent)
        if pcall(GameTooltip.SetUnit, GameTooltip, unit) then
            GameTooltip:Show()
            GameTooltip:SetFrameStrata("TOOLTIP")
            GameTooltip:SetFrameLevel(100)
        end
    end)
    container:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Create MANA orb FIRST (LARGER, background, NO galaxies)
    container.manaOrb = CreateSingleOrb(container, "RCPartyManaOrb"..index, manaSize, "MDO_orb_filling8.tga", swirlTextures, true)
    container.manaOrb:SetPoint("CENTER", container, "CENTER", 0, 0)
    
    -- Tint the mana orb gloss overlay to blue (removes black appearance)
    if container.manaOrb.bg then
        container.manaOrb.bg:SetVertexColor(0.4, 0.6, 0.9, 0.7)  -- Blue tinted gloss
    end
    
    -- Create HEALTH orb (SMALLER, centered on mana orb, on top, WITH galaxies)
    container.healthOrb = CreateSingleOrb(container, "RCPartyHealthOrb"..index, healthSize, "MDO_orb_filling6.tga", swirlTextures, false)
    container.healthOrb:SetPoint("CENTER", container.manaOrb, "CENTER", 0, 0)
    container.healthOrb:SetFrameLevel(container.manaOrb:GetFrameLevel() + 5)  -- Health on top of mana
    
    -- Set initial colors
    local r, g, b = GetClassColor(unit)
    container.healthOrb.filling:SetVertexColor(r or 0.5, g or 0.5, b or 0.5, 1)
    if container.healthOrb.galaxy1 then container.healthOrb.galaxy1.texture:SetVertexColor(r or 1, g or 1, b or 1, 1) end
    if container.healthOrb.galaxy2 then container.healthOrb.galaxy2.texture:SetVertexColor(r or 1, g or 1, b or 1, 1) end
    if container.healthOrb.galaxy3 then container.healthOrb.galaxy3.texture:SetVertexColor(r or 1, g or 1, b or 1, 1) end
    
    container.manaOrb.filling:SetVertexColor(0.2, 0.7, 1.0, 1)
    
    -- Create animated FIRE BORDER for threat (around mana orb)
    -- Create a frame for the fire border - put it BEHIND the orbs
    container.fireBorderFrame = CreateFrame("Frame", nil, container)
    container.fireBorderFrame:SetFrameLevel(container:GetFrameLevel() - 1)
    container.fireBorderFrame:SetAllPoints(container)
    
    local fireBorderSize = manaSize * 1.6  -- 60% larger than mana orb
    container.fireBorder = container.fireBorderFrame:CreateTexture(nil, "BACKGROUND")
    container.fireBorder:SetTexture(images .. "fire_frame_01.tga")
    container.fireBorder:SetSize(fireBorderSize, fireBorderSize)
    container.fireBorder:SetPoint("CENTER", container.manaOrb, "CENTER", 0, 0)
    container.fireBorder:SetVertexColor(1, 0, 0, 1)  -- Red for high threat
    container.fireBorder:Hide()  -- Hidden by default, shown on threat
    
    -- Animation state for fire border
    container.fireElapsed = 0
    container.fireCurrentFrame = 1
    
    -- Create font holder for ALL text (on top of orbs but below Blizzard UI)
    -- NOTE: Must be larger than the container to include the nameplate that sits above the mana orb
    container.fontHolder = CreateFrame("Frame", nil, container)
    container.fontHolder:SetFrameStrata("LOW")
    container.fontHolder:SetFrameLevel(container:GetFrameLevel() + 50)
    container.fontHolder:EnableMouse(false)
    -- Extend upward by manaSize*0.35 to cover the nameplate anchored above the mana orb
    local nameplateOverhang = math.floor((manaSize * 0.35) + 0.5)
    container.fontHolder:SetPoint("TOPLEFT", container, "TOPLEFT", 0, nameplateOverhang)
    container.fontHolder:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    
    -- HEALTH PERCENTAGE (large, top of health orb) - "100%"
    container.healthPct = container.fontHolder:CreateFontString(nil, "OVERLAY")
    container.healthPct:SetFont(fonts .. "crash-a-like.ttf", 18, "THINOUTLINE")
    container.healthPct:SetPoint("CENTER", container.healthOrb, "CENTER", 0, 20)
    container.healthPct:SetText("100%")
    container.healthPct:SetTextColor(1, 1, 1, 1)  -- White
    
    -- HEALTH VALUE (medium, middle of health orb) - "9.1K"
    container.healthVal = container.fontHolder:CreateFontString(nil, "OVERLAY")
    container.healthVal:SetFont(fonts .. "crash-a-like.ttf", 18, "THINOUTLINE")
    container.healthVal:SetPoint("CENTER", container.healthOrb, "CENTER", 0, -5)
    container.healthVal:SetText("9.1K")
    container.healthVal:SetTextColor(1, 1, 1, 1)  -- White
    
    -- MANA VALUE (at BOTTOM of mana orb) - "980"
    container.manaVal = container.fontHolder:CreateFontString(nil, "OVERLAY")
    container.manaVal:SetFont(fonts .. "crash-a-like.ttf", 14, "THINOUTLINE")
    container.manaVal:SetPoint("BOTTOM", container.manaOrb, "BOTTOM", 0, 10)
    container.manaVal:SetText("980")
    container.manaVal:SetTextColor(1, 1, 1, 1)  -- White
    
    -- NAMEPLATE (above mana orb) - Diablo 3 style banner
    local nameplateWidth = manaSize  -- Same width as mana orb
    local nameplateHeight = manaSize * 0.25
    
    -- Nameplate background/border
    container.nameplate = container.fontHolder:CreateTexture(nil, "ARTWORK")
    container.nameplate:SetTexture(images .. "d3_nameplate_border.tga")
    container.nameplate:SetSize(nameplateWidth, nameplateHeight)
    container.nameplate:SetPoint("BOTTOM", container.manaOrb, "TOP", 0, -8)
    container.nameplate:SetVertexColor(0.1, 0.1, 0.3, 1)  -- Deep blue
    
    -- Nameplate glow (matches nameplate size)
    container.nameplateGlow = container.fontHolder:CreateTexture(nil, "BACKGROUND")
    container.nameplateGlow:SetTexture(images .. "d3_nameplate_border_glow.tga")
    container.nameplateGlow:SetSize(nameplateWidth, nameplateHeight)
    container.nameplateGlow:SetPoint("CENTER", container.nameplate, "CENTER", 0, 0)
    container.nameplateGlow:SetVertexColor(0.1, 0.1, 0.2, 0.5)  -- Dark blue glow
    
    -- ROLE ICON (anchored to bottom of mana orb, small size)
    local roleIconSize = manaSize * 0.20  -- Small icon
    container.roleIcon = container.fontHolder:CreateTexture(nil, "OVERLAY")
    container.roleIcon:SetSize(roleIconSize, roleIconSize)
    container.roleIcon:SetPoint("TOP", container.manaOrb, "BOTTOM", 0, 8)
    container.roleIcon:Hide()  -- Hidden by default, shown when role is assigned
    
    -- NAME TEXT (on the nameplate) - larger font
    container.nameText = container.fontHolder:CreateFontString(nil, "OVERLAY")
    container.nameText:SetFont(fonts .. "crash-a-like.ttf", 20, "OUTLINE")
    container.nameText:SetPoint("CENTER", container.nameplate, "CENTER", 0, 1)
    container.nameText:SetText("")
    container.nameText:SetTextColor(1, 1, 1, 1)  -- White text
    
    -- CAST BAR (Dragon flame texture below mana orb)
    local dragonSize = manaSize * 1.1  -- Scale to fit nicely below mana orb
    
    container.castBar = CreateFrame("Frame", nil, container.fontHolder)
    container.castBar:SetSize(dragonSize, dragonSize * 0.5)  -- Shorter height to fit arc shape
    container.castBar:SetPoint("TOP", container.manaOrb, "BOTTOM", 0, manaSize * 0.35)  -- Edge touches mana orb
    container.castBar:SetFrameLevel(container.fontHolder:GetFrameLevel() + 2)
    container.castBar:Hide()
    container.castBar.dragonSize = dragonSize  -- Store for UpdateProgress
    
    -- Dragon flame texture (reveals progressively) - SOLID and BRIGHT
    container.castBar.dragonTexture = container.castBar:CreateTexture(nil, "OVERLAY")
    container.castBar.dragonTexture:SetTexture(images .. "dragon_castbar.tga")
    container.castBar.dragonTexture:SetSize(dragonSize, dragonSize * 0.5)
    container.castBar.dragonTexture:SetPoint("LEFT", container.castBar, "LEFT", 0, 0)
    container.castBar.dragonTexture:SetVertexColor(1, 0.9, 0.3, 1)  -- Bright gold
    container.castBar.dragonTexture:SetBlendMode("BLEND")  -- Solid blend mode
    
    -- Background dragon (dim, shows full arc)
    container.castBar.dragonBg = container.castBar:CreateTexture(nil, "ARTWORK")
    container.castBar.dragonBg:SetTexture(images .. "dragon_castbar.tga")
    container.castBar.dragonBg:SetSize(dragonSize, dragonSize * 0.5)
    container.castBar.dragonBg:SetPoint("CENTER", container.castBar, "CENTER", 0, 0)
    container.castBar.dragonBg:SetVertexColor(0.3, 0.3, 0.3, 0.8)  -- Darker grey, more visible
    container.castBar.dragonBg:SetBlendMode("BLEND")  -- Solid blend mode
    
    -- Spell name text (overlayed on cast bar)
    container.castBar.spellName = container.castBar:CreateFontString(nil, "OVERLAY")
    container.castBar.spellName:SetFont(fonts .. "crash-a-like.ttf", 12, "OUTLINE")
    container.castBar.spellName:SetPoint("CENTER", container.castBar, "CENTER", 0, 0)  -- Centered on dragon
    container.castBar.spellName:SetTextColor(1, 0.82, 0, 1)  -- Gold
    container.castBar.spellName:SetText("")
    
    -- Cast time text (below spell name on the cast bar)
    container.castBar.castTime = container.castBar:CreateFontString(nil, "OVERLAY")
    container.castBar.castTime:SetFont(fonts .. "crash-a-like.ttf", 10, "OUTLINE")
    container.castBar.castTime:SetPoint("TOP", container.castBar.spellName, "BOTTOM", 0, -1)
    container.castBar.castTime:SetTextColor(0.8, 0.8, 0.8, 1)
    container.castBar.castTime:SetText("")
    
    -- Cast bar state variables
    container.castBar.casting = false
    container.castBar.channeling = false
    container.castBar.startTime = 0
    container.castBar.endTime = 0
    container.castBar.spellID = nil
    container.castBar.activeColor = {1, 0.9, 0.3}  -- Bright gold
    
    -- Function to update dragon fill (using alpha fade from right to left based on progress)
    container.castBar.UpdateProgress = function(self, progress)
        local r, g, b = self.activeColor[1] or 1, self.activeColor[2] or 0.9, self.activeColor[3] or 0.3
        local size = self.dragonSize or dragonSize
        
        -- Use texture coordinates to reveal the dragon progressively
        -- progress 0 = nothing shown, progress 1 = full dragon
        local texRight = math.max(0.01, progress)  -- Reveal from 0 to 1
        
        -- Clear and reset the dragon texture positioning
        self.dragonTexture:ClearAllPoints()
        self.dragonTexture:SetPoint("LEFT", self, "LEFT", 0, 0)
        self.dragonTexture:SetTexCoord(0, texRight, 0, 1)
        self.dragonTexture:SetWidth(size * progress)
        self.dragonTexture:SetHeight(size * 0.5)
        self.dragonTexture:SetVertexColor(r, g, b, 1)
        
        -- Keep the background at full but dim
        self.dragonBg:SetTexCoord(0, 1, 0, 1)
    end
    
    -- OnUpdate for cast progress
    container.castBar:SetScript("OnUpdate", function(self, elapsed)
        if not self.casting and not self.channeling then return end
        
        local currentTime = GetTime()
        local progress
        
        if self.channeling then
            -- Channeling goes backwards
            progress = (self.endTime - currentTime) / (self.endTime - self.startTime)
        else
            -- Normal cast goes forwards
            progress = (currentTime - self.startTime) / (self.endTime - self.startTime)
        end
        
        progress = math.max(0, math.min(1, progress))
        self:UpdateProgress(progress)
        
        -- Update cast time text
        local remaining = self.endTime - currentTime
        if remaining > 0 then
            self.castTime:SetText(string.format("%.1fs", remaining))
        end
        
        -- Check if cast is complete
        if currentTime >= self.endTime then
            self.casting = false
            self.channeling = false
            self:Hide()
        end
    end)
    
    container:Show()
    return container
end

-- Create player orb (index 1)
orbFrames[1] = CreateStackedOrbFrame("player", 1)
orbFrames[1]:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 50, -50)

-- Create party orbs (index 2-5) - hidden by default
for i = 1, 4 do
    orbFrames[i+1] = CreateStackedOrbFrame("party"..i, i+1)
    orbFrames[i+1]:Hide()
end

-- Create target orb (index 6) - hidden by default
orbFrames[6] = CreateStackedOrbFrame("target", 6)
orbFrames[6]:Hide()

-- Create party target orbs (index 7-10)
for i = 1, 4 do
    orbFrames[i+6] = CreateStackedOrbFrame("party"..i.."target", i+6)
    orbFrames[i+6]:Hide()
end

-----------------------------------------------------------
-- 6b. SECURE GEOMETRY PROXY
-----------------------------------------------------------
-- The orb containers inherit SecureUnitButtonTemplate so they stay
-- click-to-target / modifier-to-cast. That also makes them PROTECTED:
-- SetSize, SetPoint and ClearAllPoints are all blocked while in combat
-- lockdown, which is what produced:
--     ADDON_ACTION_BLOCKED: RCPartyOrbFrame1:SetSize()
--
-- Restricted snippets running inside a SecureHandler ARE permitted to
-- change protected frame geometry mid-combat. So: all layout maths stays
-- in normal Lua, the result is serialised into one string attribute, and
-- the snippet below applies it. SetAttribute is not itself protected, so
-- the insecure half of this is legal at any time.
--
-- Payload: records separated by ";", fields by ","
--     index,width,height,point,relIndex,relPoint,x,y
-- relIndex 0 == UIParent. width/height of 0 means "don't resize".
-- point of "-" means "don't reposition".

local orbSizer
local sizerReady = false
local pendingGeom = nil
local geomSerial = 0

do
    local ok, handler = pcall(CreateFrame, "Frame", "RCPartyOrbsSizer", UIParent,
                              "SecureHandlerAttributeTemplate")
    if ok and handler then
        orbSizer = handler

        orbSizer:SetFrameRef("uiparent", UIParent)
        for i = 1, 10 do
            if orbFrames[i] then
                orbSizer:SetFrameRef("orb" .. i, orbFrames[i])
            end
        end

        -- Cache the refs inside the restricted environment once.
        orbSizer:Execute([[
            orbs = newtable()
            uiparent = self:GetFrameRef("uiparent")
            for i = 1, 10 do
                orbs[i] = self:GetFrameRef("orb" .. i)
            end
        ]])

        orbSizer:SetAttribute("_onattributechanged", [[
            if name ~= "orbgeom" then return end
            if not value or value == "" then return end

            local records = newtable(strsplit(";", value))
            for r = 1, #records do
                local rec = records[r]
                if rec and rec ~= "" then
                    local idx, w, h, pt, relIdx, relPt, x, y = strsplit(",", rec)
                    idx = tonumber(idx)
                    local f = idx and orbs[idx]
                    if f then
                        w = tonumber(w)
                        h = tonumber(h)
                        if w and h and w > 0 and h > 0 then
                            f:SetWidth(w)
                            f:SetHeight(h)
                        end
                        if pt and pt ~= "-" then
                            relIdx = tonumber(relIdx)
                            local rel
                            if relIdx == 0 then
                                rel = uiparent
                            elseif relIdx then
                                rel = orbs[relIdx]
                            end
                            if rel then
                                f:ClearAllPoints()
                                f:SetPoint(pt, rel, relPt, tonumber(x) or 0, tonumber(y) or 0)
                            end
                        end
                    end
                end
            end
        ]])

        sizerReady = true
    end
end

-- Map a saved frame name back to an index the snippet understands.
function RCPartyOrbs_RelIndex(frameName)
    if not frameName or frameName == "UIParent" then return 0 end
    local n = tostring(frameName):match("^RCPartyOrbFrame(%d+)$")
    if n then return tonumber(n) end
    return 0  -- unknown anchor: fall back to UIParent
end

-- Insecure fallback, used only if SecureHandlerAttributeTemplate is missing.
local function ApplyGeometryDirect(records)
    for i = 1, #records do
        local rec = records[i]
        local f = orbFrames[rec[1]]
        if f then
            local w, h = rec[2], rec[3]
            if w and h and w > 0 and h > 0 then
                f:SetSize(w, h)
            end
            local pt = rec[4]
            if pt then
                local relIdx = rec[5] or 0
                local rel = (relIdx == 0) and UIParent or orbFrames[relIdx]
                if rel then
                    f:ClearAllPoints()
                    f:SetPoint(pt, rel, rec[6], rec[7] or 0, rec[8] or 0)
                end
            end
        end
    end
end

-- records: array of { index, width, height, point, relIndex, relPoint, x, y }
-- Trailing fields may be omitted (resize-only or move-only records).
function RCPartyOrbs_ApplyGeometry(records)
    if not records or #records == 0 then return end

    if sizerReady then
        local parts = {}
        for i = 1, #records do
            local r = records[i]
            parts[#parts + 1] = table.concat({
                r[1],
                r[2] or 0,
                r[3] or 0,
                r[4] or "-",
                r[5] or 0,
                r[6] or "-",
                r[7] or 0,
                r[8] or 0,
            }, ",")
        end
        -- Trailing serial guarantees the payload always differs, so the
        -- handler fires even when the geometry is unchanged. It parses to a
        -- nil index and is skipped by the snippet.
        geomSerial = geomSerial + 1
        parts[#parts + 1] = "#" .. geomSerial
        orbSizer:SetAttribute("orbgeom", table.concat(parts, ";"))
        return
    end

    if InCombatLockdown() then
        pendingGeom = records
        return
    end
    ApplyGeometryDirect(records)
end

-- Flush deferred geometry when the fallback path had to wait out combat.
local geomFlusher = CreateFrame("Frame")
geomFlusher:RegisterEvent("PLAYER_REGEN_ENABLED")
geomFlusher:SetScript("OnEvent", function()
    if pendingGeom then
        local queued = pendingGeom
        pendingGeom = nil
        ApplyGeometryDirect(queued)
    end
end)

-----------------------------------------------------------
-- 7. LAYOUT AND POSITIONING
-----------------------------------------------------------

-- Estimate an orb's on-screen centre from its SAVED anchor (relative to
-- UIParent), rather than reading live GetCenter(). Inside PositionOrbs the
-- live centre is unreliable: at load and right after any reposition the frame
-- hasn't settled into its just-applied position, so GetCenter reports a stale
-- (often mid-screen) value. That made the target-orb "flip above near the
-- bottom edge" decision wrong until the user toggled orientation, which
-- re-ran PositionOrbs after the orb had settled. Reading the intended anchor
-- makes the flip deterministic on the first pass.
local function AnchorScreenCenter(pos, w, h, screenW, screenH)
    if not pos then return nil, nil end
    -- Only UIParent-relative anchors can be resolved without the live frame.
    if pos.relativeTo and pos.relativeTo ~= "UIParent" then return nil, nil end
    local rp = (pos.relativePoint or "CENTER"):upper()
    local pt = (pos.point or "CENTER"):upper()

    -- Reference point on UIParent (WoW y-axis points up: bottom = 0).
    local refY
    if rp:find("BOTTOM") then refY = 0
    elseif rp:find("TOP") then refY = screenH
    else refY = screenH * 0.5 end
    local refX
    if rp:find("LEFT") then refX = 0
    elseif rp:find("RIGHT") then refX = screenW
    else refX = screenW * 0.5 end

    -- Offset from the orb's own anchor point to its centre.
    local adjY = 0
    if pt:find("TOP") then adjY = -h * 0.5
    elseif pt:find("BOTTOM") then adjY = h * 0.5 end
    local adjX = 0
    if pt:find("LEFT") then adjX = w * 0.5
    elseif pt:find("RIGHT") then adjX = -w * 0.5 end

    return refX + (pos.x or 0) + adjX, refY + (pos.y or 0) + adjY
end

-- Position orbs based on orientation setting or saved positions
function PositionOrbs()
    local spacing = RCPartyOrbsDB.orbSpacing or 20
    local targetSpacing = RCPartyOrbsDB.targetOrbSpacing or 15  -- Separate spacing for targets
    local isVertical = RCPartyOrbsDB.partyOrientation == "vertical"

    -- Clamp negative spacing so orb bodies can never physically overlap. A
    -- target orb sitting under a party orb loses (party orbs render at a higher
    -- frame level), so any overlap buries the target entirely.
    if targetSpacing < 0 then targetSpacing = 0 end

    -- The unit name sits ABOVE each orb by ~35% of its height (see fontHolder
    -- overhang in CreateStackedOrbFrame). In horizontal layout the target orb
    -- goes above/below the party orb, so that name text lands in the gap
    -- between them. Add the relevant overhang to the vertical gap so the name
    -- clears the neighbouring orb instead of overlapping it. Only needed when
    -- names are shown, and only vertically (horizontal gaps aren't affected).
    local orbSize = RCPartyOrbsDB.orbSize or ORB_SIZE
    local targetScale = (RCPartyOrbsDB.targetOrbScale or 75) / 100
    local showName = RCPartyOrbsDB.showName ~= false
    local partyOverhang  = math.floor((orbSize * 1.3 * 0.35) + 0.5)
    local targetOverhang = math.floor((orbSize * targetScale * 1.3 * 0.35) + 0.5)
    -- target below party: its own name is in the gap
    local gapBelow = targetSpacing + (showName and targetOverhang or 0)
    -- target above party: the party orb's name is in the gap
    local gapAbove = targetSpacing + (showName and partyOverhang or 0)

    -- Anchors are collected, then handed to the secure proxy in one call so
    -- they apply correctly even mid-combat (containers are protected frames).
    local geom = {}

    -- Player orb position (restore saved or default to top-left)
    if RCPartyOrbsDB.orbPositions and RCPartyOrbsDB.orbPositions["player"] then
        local pos = RCPartyOrbsDB.orbPositions["player"]
        geom[#geom + 1] = { 1, 0, 0, pos.point, RCPartyOrbs_RelIndex(pos.relativeTo),
                            pos.relativePoint, pos.x, pos.y }
    else
        geom[#geom + 1] = { 1, 0, 0, "TOPLEFT", 0, "TOPLEFT", 50, -50 }
    end

    -- Position party orbs - ALWAYS use orientation-based positioning (no saved positions)
    for i = 2, 5 do
        if orbFrames[i] then
            if isVertical then
                geom[#geom + 1] = { i, 0, 0, "TOP", i - 1, "BOTTOM", 0, -spacing }
            else
                geom[#geom + 1] = { i, 0, 0, "LEFT", i - 1, "RIGHT", spacing, 0 }
            end
        end
    end

    -- Smart target orb placement: detect if orbs are near a screen edge and flip
    -- the target orb to the opposite side so it stays on-screen and uncluttered.
    -- Horizontal mode: target orbs normally go below; flip ABOVE when near bottom.
    -- Vertical mode:   target orbs normally go right;  flip LEFT  when near right edge.
    local screenH = UIParent:GetHeight()
    local screenW = UIParent:GetWidth()
    -- Prefer the intended (saved) player position; fall back to live centre,
    -- then to screen centre. See AnchorScreenCenter for why live is unreliable.
    local playerSize = orbSize * 1.3  -- container = mana orb size
    local pX, pY = AnchorScreenCenter(
        RCPartyOrbsDB.orbPositions and RCPartyOrbsDB.orbPositions["player"],
        playerSize, playerSize, screenW, screenH)
    if not pX or not pY then
        pX, pY = orbFrames[1]:GetCenter()
    end
    pX = pX or (screenW * 0.5)
    pY = pY or (screenH * 0.5)
    local targetAbove = (not isVertical) and (pY < screenH * 0.45)
    local targetLeft  = isVertical        and (pX > screenW * 0.55)

    -- Position target orb (player's target) - ALWAYS anchor to player orb
    if orbFrames[6] then
        if isVertical then
            if targetLeft then
                geom[#geom + 1] = { 6, 0, 0, "RIGHT", 1, "LEFT", -targetSpacing, 0 }
            else
                geom[#geom + 1] = { 6, 0, 0, "LEFT", 1, "RIGHT", targetSpacing, 0 }
            end
        else
            if targetAbove then
                geom[#geom + 1] = { 6, 0, 0, "BOTTOM", 1, "TOP", 0, gapAbove }
            else
                geom[#geom + 1] = { 6, 0, 0, "TOP", 1, "BOTTOM", 0, -gapBelow }
            end
        end
    end

    -- Position party target orbs (index 7-10) - ALWAYS anchored to corresponding party member
    -- party1target anchors to party1, party2target to party2, etc.
    for i = 7, 10 do
        if orbFrames[i] then
            local parentIdx = (i - 6) + 1  -- party1 is index 2, party2 is index 3, etc.
            if orbFrames[parentIdx] then
                if isVertical then
                    if targetLeft then
                        geom[#geom + 1] = { i, 0, 0, "RIGHT", parentIdx, "LEFT", -targetSpacing, 0 }
                    else
                        geom[#geom + 1] = { i, 0, 0, "LEFT", parentIdx, "RIGHT", targetSpacing, 0 }
                    end
                else
                    if targetAbove then
                        geom[#geom + 1] = { i, 0, 0, "BOTTOM", parentIdx, "TOP", 0, gapAbove }
                    else
                        geom[#geom + 1] = { i, 0, 0, "TOP", parentIdx, "BOTTOM", 0, -gapBelow }
                    end
                end
            end
        end
    end

    RCPartyOrbs_ApplyGeometry(geom)
end

-- Toggle party orb orientation
function RCPartyOrbs_ToggleOrientation()
    if RCPartyOrbsDB.partyOrientation == "vertical" then
        RCPartyOrbsDB.partyOrientation = "horizontal"
    else
        RCPartyOrbsDB.partyOrientation = "vertical"
    end
    
    PositionOrbs()
    print("RC Party Orbs: Orientation set to " .. RCPartyOrbsDB.partyOrientation)
end

-----------------------------------------------------------
-- 8. DATA UPDATE ENGINE
-----------------------------------------------------------

-- Update a single orb fill
local function UpdateOrbFill(orb, value, maxValue, r, g, b)
    if not orb or not orb.filling then return end
    
    local pct = maxValue > 0 and (value / maxValue) or 0
    -- Clamp pct to 0-1 range (can exceed 1 with temporary HP buffs)
    if pct > 1 then pct = 1 end
    if pct < 0 then pct = 0 end
    
    local size = orb:GetWidth()
    
    local fillHeight = (size - 6) * pct
    if fillHeight < 1 then fillHeight = 1 end
    
    orb.filling:SetHeight(fillHeight)
    orb.filling:SetTexCoord(0, 1, 1 - pct, 1)
    if r and g and b then
        orb.filling:SetVertexColor(r, g, b, 1)
    end
    
    -- Update galaxy alpha (pct already clamped 0-1)
    local alpha = 0.3 + (pct * 0.7)
    if orb.galaxy1 then orb.galaxy1:SetAlpha(alpha) end
    if orb.galaxy2 then orb.galaxy2:SetAlpha(alpha) end
    if orb.galaxy3 then orb.galaxy3:SetAlpha(alpha) end
end

-- Update a stacked orb frame
function UpdateOrbHealth(frame)
    if not frame then return end
    
    local unit = frame.unit
    if not unit then return end
    if not UnitExists(unit) and not testMode then return end
    
    local h, maxH, p, maxP, name, r, g, b
    local realH, realP
    local powerType = UnitPowerType(unit) or 0
    if RCPartyOrbs_Secret(powerType) then powerType = 0 end
    local isOffline = false
    local isOutOfRange = false
    
    if testMode and testPartyData[unit] and not UnitExists(unit) then
        local data = testPartyData[unit]
        h, maxH, p, maxP, name = data.h, data.maxH, data.p, data.maxP, data.name
        r, g, b = data.r, data.g, data.b
        frame:Show()
    else
        h, maxH = UnitHealth(unit), UnitHealthMax(unit)
        p = UnitPower(unit, powerType) or 0
        maxP = UnitPowerMax(unit, powerType) or 0
        name = UnitName(unit)
        -- Retail / WoW Forever hide exact values in combat: fill from the
        -- readable percentage (0-100 scale) and keep the real value for text
        realH, realP = h, p
        if RCPartyOrbs_Secret(h) or RCPartyOrbs_Secret(maxH) then
            h, maxH = RCPartyOrbs_Percent("health", unit) or 100, 100
        end
        if RCPartyOrbs_Secret(p) or RCPartyOrbs_Secret(maxP) then
            p, maxP = RCPartyOrbs_Percent("power", unit, powerType) or 0, 100
        end
        
        -- Health color: custom color only applies to player orb, party members always use class color
        if unit == "player" then
            local charHealthColor = GetCharacterColor("healthColor")
            if charHealthColor and charHealthColor.r and charHealthColor.g and charHealthColor.b then
                r, g, b = charHealthColor.r, charHealthColor.g, charHealthColor.b
            else
                r, g, b = GetClassColor(unit)
            end
        else
            -- Party members and targets always use their class color (cached for out of range)
            r, g, b = GetClassColorCached(unit)
        end
        
        -- Check if unit is offline (only for party members, not player or targets)
        if unit ~= "player" and not string.find(unit, "target") then
            local connected = UnitIsConnected(unit)
            isOffline = not RCPartyOrbs_Secret(connected) and not connected
            -- Check if unit is out of range (only works for party/raid members)
            if not isOffline and UnitInRange then
                local inRange, checkedRange = UnitInRange(unit)
                if RCPartyOrbs_Secret(inRange) or RCPartyOrbs_Secret(checkedRange) then
                    checkedRange = false
                end
                if checkedRange then
                    isOutOfRange = not inRange
                end
            end
        end
    end
    
    local hPct = maxH > 0 and (h / maxH) or 0
    local pPct = maxP > 0 and (p / maxP) or 0
    
    -- Handle OFFLINE state - black orbs with "Offline" text
    if isOffline then
        -- Set orb colors to black
        if frame.healthOrb then
            UpdateOrbFill(frame.healthOrb, 1, 1, 0.1, 0.1, 0.1)  -- Black/dark grey
            if frame.healthOrb.galaxy1 then frame.healthOrb.galaxy1.texture:SetVertexColor(0.2, 0.2, 0.2, 1) end
            if frame.healthOrb.galaxy2 then frame.healthOrb.galaxy2.texture:SetVertexColor(0.2, 0.2, 0.2, 1) end
            if frame.healthOrb.galaxy3 then frame.healthOrb.galaxy3.texture:SetVertexColor(0.2, 0.2, 0.2, 1) end
        end
        if frame.manaOrb then
            UpdateOrbFill(frame.manaOrb, 1, 1, 0.1, 0.1, 0.1)  -- Black/dark grey
        end
        
        -- Show "Offline" text
        if frame.healthPct then
            frame.healthPct:SetText("Offline")
            frame.healthPct:SetTextColor(0.5, 0.5, 0.5, 1)  -- Grey text
            frame.healthPct:Show()
        end
        if frame.healthVal then
            frame.healthVal:Hide()
        end
        if frame.manaVal then
            frame.manaVal:Hide()
        end
        if frame.nameText then
            frame.nameText:SetText(name or "")
            frame.nameText:SetTextColor(0.5, 0.5, 0.5, 1)  -- Grey text
            frame.nameText:Show()
            if frame.nameplate then frame.nameplate:Show() end
            if frame.nameplateGlow then frame.nameplateGlow:Show() end
            if frame.roleIcon then frame.roleIcon:Hide() end  -- Hide role icon when offline
        end
        
        -- Hide threat border for offline
        if frame.fireBorder then frame.fireBorder:Hide() end
        return
    end
    
    -- Handle DEAD state - grey orbs with "DEAD" text and skull indicator
    local isDead = RCPartyOrbs_True(UnitIsDead(unit)) or RCPartyOrbs_True(UnitIsGhost(unit))
    if isDead and not testMode then
        -- Set orb colors to grey/death colors
        if frame.healthOrb then
            UpdateOrbFill(frame.healthOrb, 0, 1, 0.3, 0.3, 0.3)  -- Empty grey orb
            if frame.healthOrb.galaxy1 then frame.healthOrb.galaxy1.texture:SetVertexColor(0.3, 0.3, 0.3, 0.5) end
            if frame.healthOrb.galaxy2 then frame.healthOrb.galaxy2.texture:SetVertexColor(0.3, 0.3, 0.3, 0.5) end
            if frame.healthOrb.galaxy3 then frame.healthOrb.galaxy3.texture:SetVertexColor(0.3, 0.3, 0.3, 0.5) end
        end
        if frame.manaOrb then
            UpdateOrbFill(frame.manaOrb, 0, 1, 0.2, 0.2, 0.2)  -- Empty dark grey
        end
        
        -- Show "DEAD" text in red
        if frame.healthPct then
            frame.healthPct:SetText("|cFFFF0000DEAD|r")
            frame.healthPct:SetTextColor(1, 0, 0, 1)  -- Red text
            frame.healthPct:Show()
        end
        if frame.healthVal then
            frame.healthVal:Hide()
        end
        if frame.manaVal then
            frame.manaVal:Hide()
        end
        if frame.nameText then
            frame.nameText:SetText(name or "")
            frame.nameText:SetTextColor(0.5, 0.5, 0.5, 1)  -- Grey name
            frame.nameText:Show()
            if frame.nameplate then frame.nameplate:Show() end
            if frame.nameplateGlow then frame.nameplateGlow:Show() end
            if frame.roleIcon then frame.roleIcon:Hide() end
        end
        
        -- Hide threat border for dead units
        if frame.fireBorder then frame.fireBorder:Hide() end
        
        -- Mark frame as having a dead unit (for quick reference)
        frame.unitIsDead = true
        return
    else
        frame.unitIsDead = false
    end
    
    -- Handle OUT OF RANGE state - greyed/desaturated orbs
    local colorMult = 1.0
    local alphaMult = 1.0
    if isOutOfRange then
        colorMult = 0.4  -- Desaturate colors
        alphaMult = 0.6  -- Slightly transparent
    end
    
    -- Update health orb
    if frame.healthOrb then
        local hr, hg, hb = (r or 1) * colorMult, (g or 1) * colorMult, (b or 1) * colorMult
        if isOutOfRange then
            -- Mix with grey for desaturation effect
            hr = hr * 0.5 + 0.25
            hg = hg * 0.5 + 0.25
            hb = hb * 0.5 + 0.25
        end
        UpdateOrbFill(frame.healthOrb, h, maxH, hr, hg, hb)
        -- Color galaxies
        if frame.healthOrb.galaxy1 then frame.healthOrb.galaxy1.texture:SetVertexColor(hr, hg, hb, alphaMult) end
        if frame.healthOrb.galaxy2 then frame.healthOrb.galaxy2.texture:SetVertexColor(hr, hg, hb, alphaMult) end
        if frame.healthOrb.galaxy3 then frame.healthOrb.galaxy3.texture:SetVertexColor(hr, hg, hb, alphaMult) end
    end
    
    -- Update mana orb with power-type color (no galaxies on mana orb)
    -- Use character-specific color if set for each power type, otherwise use defaults
    if frame.manaOrb then
        local pr, pg, pb
        local _, playerClass = UnitClass("player")
        
        -- Check for character-specific color based on power type
        -- Power types: 0=mana, 1=rage, 2=focus, 3=energy, 6=runic, 12=chi
        if powerType == 1 then  -- Rage
            local charColor = GetCharacterColor("rageColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("rage", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        elseif powerType == 2 then  -- Focus
            local charColor = GetCharacterColor("focusColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("focus", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        elseif powerType == 3 then  -- Energy
            local charColor = GetCharacterColor("energyColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("energy", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        elseif powerType == 6 then  -- Runic Power
            local charColor = GetCharacterColor("runicColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("runic", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        elseif powerType == 12 then  -- Chi (Monk)
            local charColor = GetCharacterColor("chiColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("chi", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        else  -- Mana (0) or other
            local charColor = GetCharacterColor("manaColor")
            if charColor and charColor.r then
                pr, pg, pb = charColor.r, charColor.g, charColor.b
            else
                local defaultColor = GetDefaultColor("mana", playerClass)
                pr, pg, pb = defaultColor.r, defaultColor.g, defaultColor.b
            end
        end
        
        if isOutOfRange then
            pr = pr * 0.5 + 0.25
            pg = pg * 0.5 + 0.25
            pb = pb * 0.5 + 0.25
        end
        
        UpdateOrbFill(frame.manaOrb, p, maxP, pr, pg, pb)
        
        -- Tint the gloss overlay to match power color (removes black ring)
        if frame.manaOrb.bg then
            frame.manaOrb.bg:SetVertexColor(pr * 0.5 + 0.2, pg * 0.5 + 0.2, pb * 0.5 + 0.2, 0.7)
        end
    end
    
    -- Text color for out of range
    local textR, textG, textB = 1, 1, 1
    if isOutOfRange then
        textR, textG, textB = 0.6, 0.6, 0.6  -- Grey text when out of range
    end
    
    -- Update text displays based on settings
    if frame.healthPct then
        if RCPartyOrbsDB.showHealthPercentage then
            frame.healthPct:SetText(math.floor(hPct * 100) .. "%")
            frame.healthPct:SetTextColor(textR, textG, textB, 1)
            frame.healthPct:Show()
        else
            frame.healthPct:Hide()
        end
    end
    if frame.healthVal then
        if RCPartyOrbsDB.showHealthValue ~= false then
            frame.healthVal:SetText(RCPartyOrbs_Secret(realH) and RCPartyOrbs_ValueText(realH) or FormatHealth(h))
            frame.healthVal:SetTextColor(textR, textG, textB, 1)
            frame.healthVal:Show()
        else
            frame.healthVal:Hide()
        end
    end
    if frame.manaVal then
        if RCPartyOrbsDB.showManaValue ~= false then
            frame.manaVal:SetText(RCPartyOrbs_Secret(realP) and RCPartyOrbs_ValueText(realP) or FormatHealth(p))
            frame.manaVal:SetTextColor(textR, textG, textB, 1)
            frame.manaVal:Show()
        else
            frame.manaVal:Hide()
        end
    end
    if frame.nameText then
        if RCPartyOrbsDB.showName then
            -- Get level and add it to name if enabled
            local displayName = name or ""
            if RCPartyOrbsDB.showLevel ~= false then
                local level = UnitLevel(unit) or 0
                if RCPartyOrbs_Secret(level) then level = 0 end
                if level > 0 then
                    displayName = displayName .. " " .. level
                end
            end
            frame.nameText:SetText(displayName)
            frame.nameText:SetTextColor(textR, textG, textB, 1)
            frame.nameText:Show()
            -- Also show nameplate
            if frame.nameplate then frame.nameplate:Show() end
            if frame.nameplateGlow then frame.nameplateGlow:Show() end
            
            -- Update role icon if enabled
            if frame.roleIcon then
                if RCPartyOrbsDB.showRoleIcon ~= false then
                    local role = Compat.UnitGroupRolesAssigned(unit)
                    if role == "TANK" then
                        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                        frame.roleIcon:SetTexCoord(0, 0.296875, 0.34375, 0.640625)  -- Tank icon
                        frame.roleIcon:Show()
                    elseif role == "HEALER" then
                        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                        frame.roleIcon:SetTexCoord(0.296875, 0.59375, 0, 0.296875)  -- Healer icon
                        frame.roleIcon:Show()
                    elseif role == "DAMAGER" then
                        frame.roleIcon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
                        frame.roleIcon:SetTexCoord(0.296875, 0.59375, 0.34375, 0.640625)  -- DPS icon
                        frame.roleIcon:Show()
                    else
                        frame.roleIcon:Hide()
                    end
                else
                    frame.roleIcon:Hide()
                end
            end
        else
            frame.nameText:Hide()
            -- Also hide nameplate
            if frame.nameplate then frame.nameplate:Hide() end
            if frame.nameplateGlow then frame.nameplateGlow:Hide() end
            if frame.roleIcon then frame.roleIcon:Hide() end
        end
    end
    
    -- Check for dispellable debuffs and update orb color
    if not testMode then
        UpdateOrbDebuffColor(frame)
    end
end

function UpdateOrbThreat(frame)
    if not frame then return end
    if not RCPartyOrbsDB.showThreatBorders then 
        if frame.fireBorder then frame.fireBorder:Hide() end
        return 
    end
    
    -- In test mode, don't update threat based on actual threat data
    -- The test mode will set colors directly
    if testMode then
        return
    end
    
    local unit = frame.unit
    if not unit or not UnitExists(unit) then 
        if frame.fireBorder then frame.fireBorder:Hide() end
        return 
    end
    
    -- Check threat against all visible nameplates (enemies in combat)
    local highestStatus = 0
    local highestThreatPct = 0
    
    -- Helper function to check threat against a mob unit
    local function CheckThreat(mobUnit)
        if UnitExists(mobUnit) and UnitCanAttack("player", mobUnit) and UnitAffectingCombat(mobUnit) then
            local isTanking, status, threatPct = UnitDetailedThreatSituation(unit, mobUnit)
            if RCPartyOrbs_Secret(status) then status = nil end
            if RCPartyOrbs_Secret(threatPct) then threatPct = nil end
            if status and status > highestStatus then
                highestStatus = status
            end
            if threatPct and threatPct > highestThreatPct then
                highestThreatPct = threatPct
            end
        end
    end
    
    -- Check against current target
    CheckThreat("target")
    
    -- Check against focus
    CheckThreat("focus")
    
    -- Check against target's target (useful if targeting a party member)
    CheckThreat("targettarget")
    
    -- Check against boss frames (1-5)
    for i = 1, 5 do
        CheckThreat("boss" .. i)
    end
    
    -- Check against arena frames (1-5) 
    for i = 1, 5 do
        CheckThreat("arena" .. i)
    end
    
    -- Check against all nameplate units (enemies in combat range)
    for i = 1, 40 do
        CheckThreat("nameplate" .. i)
    end
    
    if frame.fireBorder then
        if highestStatus >= 2 then
            -- Has aggro (tanking) - RED
            local color = RCPartyOrbsDB.fireBorderColor or {r=1, g=0, b=0, a=1}
            frame.fireBorder:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            frame.fireBorder:Show()
        elseif highestThreatPct >= 75 then
            -- 75% to just before aggro - YELLOW
            local color = RCPartyOrbsDB.yellowBorderColor or {r=1, g=1, b=0, a=1}
            frame.fireBorder:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            frame.fireBorder:Show()
        elseif highestThreatPct >= 50 then
            -- 50% to 74% - GREEN
            local color = RCPartyOrbsDB.greenBorderColor or {r=0, g=1, b=0, a=1}
            frame.fireBorder:SetVertexColor(color.r, color.g, color.b, color.a or 1)
            frame.fireBorder:Show()
        else
            -- Below 50% threat - hide border
            frame.fireBorder:Hide()
        end
    end
end

-- Update threat border visibility based on setting
function RCPartyOrbs_UpdateThreatVisibility()
    if not RCPartyOrbsDB.showThreatBorders then
        -- Hide all fire borders
        for i = 1, 10 do
            if orbFrames[i] and orbFrames[i].fireBorder then
                orbFrames[i].fireBorder:Hide()
            end
        end
    elseif testMode then
        -- In test mode, show fire borders with their test colors
        for i = 1, 10 do
            if orbFrames[i] and orbFrames[i].fireBorder then
                orbFrames[i].fireBorder:Show()
            end
        end
    end
end

function UpdateAllOrbs()
    if not RCPartyOrbsDB or not RCPartyOrbsDB.enabled then return end
    
    -- PERFORMANCE: Only update orbs that are actually shown
    -- In raids, most orbs are hidden, so we skip them entirely
    for i = 1, 10 do
        if orbFrames[i] and orbFrames[i]:IsShown() then
            UpdateOrbHealth(orbFrames[i])
            UpdateOrbThreat(orbFrames[i])
        end
    end
end

-- Global wrapper for color picker to force update
function RCPartyOrbs_ForceUpdateAllOrbs()
    UpdateAllOrbs()
end

-- Dedicated test mode update
function UpdateTestModeOrbs()
    if not testMode then return end
    for i = 1, 6 do
        if orbFrames[i] then
            orbFrames[i]:Show()
            UpdateOrbHealth(orbFrames[i])
        end
    end
end

-----------------------------------------------------------
-- 9. GUI HANDLERS (Sliders & Fixes)
-----------------------------------------------------------

local menuUpdating = false

function RCPartyOrbs_InitSwirlDropdown()
    local d = RCPartyOrbsSwirlDropdown
    if not d then return end
    UIDropDownMenu_Initialize(d, function(self, level)
        local swirlNames = { ["bubbles"] = "Bubbles", ["galaxy"] = "Galaxy", ["iris"] = "Iris" }
        for k, v in pairs(swirlNames) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = v; info.value = k
            info.func = function(self)
                currentSwirlSet = self.value
                RCPartyOrbsDB.swirlSet = self.value
                UIDropDownMenu_SetText(d, self:GetText())
                for _, orb in ipairs(orbFrames) do UpdateOrbSwirls(orb) end
            end
            info.checked = (k == currentSwirlSet)
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(d, currentSwirlSet:gsub("^%l", string.upper))
end

-- Initialize the click modifier dropdown
function RCPartyOrbs_InitModifierDropdown()
    local d = RCPartyOrbsModifierDropdown
    if not d then return end
    
    local modifierNames = {
        ["shift"] = "Shift + Click",
        ["alt"] = "Alt + Click",
        ["ctrl"] = "Ctrl + Click"
    }
    local modifierOrder = {"shift", "alt", "ctrl"}
    
    UIDropDownMenu_Initialize(d, function(self, level)
        for _, k in ipairs(modifierOrder) do
            local v = modifierNames[k]
            local info = UIDropDownMenu_CreateInfo()
            info.text = v
            info.value = k
            info.func = function(self)
                RCPartyOrbsDB.clickModifier = self.value
                UIDropDownMenu_SetText(d, self:GetText())
                -- Update all orb modifier attributes immediately
                RCPartyOrbs_UpdateOrbModifiers()
            end
            info.checked = (k == (RCPartyOrbsDB.clickModifier or "shift"))
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    
    local currentMod = RCPartyOrbsDB.clickModifier or "shift"
    UIDropDownMenu_SetText(d, modifierNames[currentMod] or "Shift + Click")
end

-- Update all orb modifier attributes (called when dropdown changes)
function RCPartyOrbs_UpdateOrbModifiers()
    if InCombatLockdown() then
        print("|cFFFF0000RCPartyOrbs:|r Cannot change modifier during combat. Change will apply after combat.")
        return
    end
    
    local currentMod = RCPartyOrbsDB.clickModifier or "shift"
    local modNames = {["shift"]="Shift", ["alt"]="Alt", ["ctrl"]="Ctrl"}
    
    for _, orb in ipairs(orbFrames) do
        local container = orb
        local macroText = container.castMacroText or ""
        
        -- Update each modifier - active one gets macro if we have dispel spells,
        -- otherwise let the click pass through for normal spell casting
        for _, mod in ipairs({"shift", "alt", "ctrl"}) do
            if mod == currentMod and macroText ~= "" then
                container:SetAttribute(mod .. "-type1", "macro")
                container:SetAttribute(mod .. "-macrotext1", macroText)
            else
                -- Clear the attribute so shift-click passes through for spell casting
                container:SetAttribute(mod .. "-type1", nil)
                container:SetAttribute(mod .. "-macrotext1", nil)
            end
        end
    end
    
    print("|cFF00FF00RCPartyOrbs:|r Click modifier changed to " .. (modNames[currentMod] or "Shift") .. "+Click")
end

-- Initialize the debuff sound dropdown
function RCPartyOrbs_InitDebuffSoundDropdown()
    local d = RCPartyOrbsDebuffSoundDropdown
    if not d then return end
    
    UIDropDownMenu_Initialize(d, function(self, level)
        for _, soundKey in ipairs(DEBUFF_SOUND_ORDER) do
            local soundData = DEBUFF_SOUNDS[soundKey]
            if soundData then
                local info = UIDropDownMenu_CreateInfo()
                info.text = soundData.name
                info.value = soundKey
                info.func = function(self)
                    RCPartyOrbsDB.debuffSound = self.value
                    UIDropDownMenu_SetText(d, DEBUFF_SOUNDS[self.value].name)
                    
                    -- Play preview of the selected sound
                    local selectedSound = DEBUFF_SOUNDS[self.value]
                    if selectedSound and selectedSound.file then
                        PlaySoundFile(selectedSound.file, "Master")
                    else
                        PlaySound(SOUNDKIT.READY_CHECK, "Master")
                    end
                end
                info.checked = (soundKey == (RCPartyOrbsDB.debuffSound or "default"))
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end)
    
    local currentSound = RCPartyOrbsDB.debuffSound or "default"
    local soundData = DEBUFF_SOUNDS[currentSound]
    UIDropDownMenu_SetText(d, soundData and soundData.name or "Default (Ready Check)")
end

-----------------------------------------------------------
-- RETAIL DROPDOWN REPLACEMENTS
-- UIDropDownMenuTemplate is removed in Retail 10.0+.
-- These cycling button widgets replicate the three dropdowns
-- using only CreateFrame/Button, which work on every version.
-- They are created lazily (once) when the GUI first opens.
-----------------------------------------------------------

-- Creates a cycling button control: [◄] [  label  ] [►]
-- parent   : parent frame (RCPartyOrbsGUI)
-- anchorX/Y: TOPLEFT offsets matching the old dropdown positions
-- values   : ordered list of value keys
-- labels   : map from key -> display string
-- getCurrent : function() -> current key
-- onChange   : function(newKey) called when value changes
local function CreateRetailCycler(parent, anchorX, anchorY, width, values, labels, getCurrent, onChange)
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 26)
    container:SetPoint("TOPLEFT", anchorX, anchorY)

    -- Left arrow button
    local leftBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    leftBtn:SetSize(22, 22)
    leftBtn:SetPoint("LEFT", 0, 0)
    leftBtn:SetText("◄")
    leftBtn:GetFontString():SetFont(leftBtn:GetFontString():GetFont(), 10)

    -- Display label
    local label = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", leftBtn, "RIGHT", 4, 0)
    label:SetPoint("RIGHT", container, "RIGHT", -26, 0)
    label:SetJustifyH("CENTER")
    label:SetWordWrap(false)

    -- Right arrow button
    local rightBtn = CreateFrame("Button", nil, container, "UIPanelButtonTemplate")
    rightBtn:SetSize(22, 22)
    rightBtn:SetPoint("RIGHT", 0, 0)
    rightBtn:SetText("►")
    rightBtn:GetFontString():SetFont(rightBtn:GetFontString():GetFont(), 10)

    local function refresh()
        label:SetText(labels[getCurrent()] or "?")
    end

    local function cycle(dir)
        local cur = getCurrent()
        local idx = 1
        for i, v in ipairs(values) do
            if v == cur then idx = i; break end
        end
        idx = idx + dir
        if idx < 1 then idx = #values end
        if idx > #values then idx = 1 end
        onChange(values[idx])
        refresh()
    end

    leftBtn:SetScript("OnClick", function() cycle(-1) end)
    rightBtn:SetScript("OnClick", function() cycle(1) end)

    container.Refresh = refresh
    refresh()
    return container
end

-- Holds the three Retail cycler widgets (created once)
local retailCyclers = {}

-- Called from RCPartyOrbs_UpdateMenu on Retail to build/refresh cycling buttons
local function RCPartyOrbs_EnsureRetailCyclers()
    if not RCPartyOrbs_Version.isRetail then return end
    local parent = RCPartyOrbsGUI
    if not parent then return end

    -- ── Swirl cycler ────────────────────────────────────────────────
    if not retailCyclers.swirl then
        local swirlValues = { "bubbles", "galaxy", "iris" }
        local swirlLabels = { bubbles = "Bubbles", galaxy = "Galaxy", iris = "Iris" }
        retailCyclers.swirl = CreateRetailCycler(
            parent, 10, -118, 160,
            swirlValues, swirlLabels,
            function() return RCPartyOrbsDB and RCPartyOrbsDB.swirlSet or "bubbles" end,
            function(val)
                currentSwirlSet = val
                RCPartyOrbsDB.swirlSet = val
                for _, orb in ipairs(orbFrames) do UpdateOrbSwirls(orb) end
            end
        )
    else
        retailCyclers.swirl:Refresh()
    end

    -- ── Modifier cycler ─────────────────────────────────────────────
    if not retailCyclers.modifier then
        local modValues = { "shift", "alt", "ctrl" }
        local modLabels = { shift = "Shift + Click", alt = "Alt + Click", ctrl = "Ctrl + Click" }
        retailCyclers.modifier = CreateRetailCycler(
            parent, 110, -203, 180,
            modValues, modLabels,
            function() return RCPartyOrbsDB and RCPartyOrbsDB.clickModifier or "shift" end,
            function(val)
                RCPartyOrbsDB.clickModifier = val
                RCPartyOrbs_UpdateOrbModifiers()
            end
        )
    else
        retailCyclers.modifier:Refresh()
    end

    -- ── Debuff Sound cycler ─────────────────────────────────────────
    if not retailCyclers.sound then
        -- Build display labels from DEBUFF_SOUNDS table
        local soundLabels = {}
        for k, v in pairs(DEBUFF_SOUNDS) do
            soundLabels[k] = v.name
        end
        retailCyclers.sound = CreateRetailCycler(
            parent, 180, -293, 190,
            DEBUFF_SOUND_ORDER, soundLabels,
            function() return RCPartyOrbsDB and RCPartyOrbsDB.debuffSound or "default" end,
            function(val)
                RCPartyOrbsDB.debuffSound = val
                -- Play preview
                local s = DEBUFF_SOUNDS[val]
                if s and s.file then
                    PlaySoundFile(s.file, "Master")
                else
                    PlaySound(SOUNDKIT.READY_CHECK, "Master")
                end
            end
        )
    else
        retailCyclers.sound:Refresh()
    end
end

function RCPartyOrbs_UpdateMenu()
    menuUpdating = true
    RCPartyOrbs_EnsureRetailCyclers()  -- build/refresh Retail cycling buttons
    RCPartyOrbs_InitSwirlDropdown()
    RCPartyOrbs_InitModifierDropdown()
    RCPartyOrbs_InitDebuffSoundDropdown()
    
    -- DATABASE SANITY CHECK
    local scale = RCPartyOrbsDB.scale or 1.0
    local size = RCPartyOrbsDB.orbSize or 80
    local spacing = RCPartyOrbsDB.orbSpacing or 15
    
    -- Update Sliders
    if RCPartyOrbsScaleSlider then 
        RCPartyOrbsScaleSlider:SetValue(scale * 100) 
    end
    if RCPartyOrbsSizeSlider then 
        RCPartyOrbsSizeSlider:SetValue(size) 
    end
    if RCPartyOrbsSpacingSlider then 
        RCPartyOrbsSpacingSlider:SetValue(spacing) 
    end
    
    -- Update Font Size Slider
    local fontScale = RCPartyOrbsDB.fontScale or 100
    if RCPartyOrbsFontSizeSlider then
        RCPartyOrbsFontSizeSlider:SetValue(fontScale)
    end
    if RCPartyOrbsFontSizeValueText then
        RCPartyOrbsFontSizeValueText:SetText(fontScale .. "%")
    end
    
    -- Update Checkboxes
    if ShowNameCheckButton then 
        ShowNameCheckButton:SetChecked(RCPartyOrbsDB.showName) 
    end
    if ShowHealthPercentageCheckButton then 
        ShowHealthPercentageCheckButton:SetChecked(RCPartyOrbsDB.showHealthPercentage) 
    end
    if EnableOrbsCheckButton then 
        EnableOrbsCheckButton:SetChecked(RCPartyOrbsDB.enabled) 
    end
    if ShowThreatBordersCheckButton then
        ShowThreatBordersCheckButton:SetChecked(RCPartyOrbsDB.showThreatBorders)
    end
    if ShowDebuffColorsCheckButton then
        ShowDebuffColorsCheckButton:SetChecked(RCPartyOrbsDB.showDebuffColors ~= false)
    end
    if ShowHelpOnLoginCheckButton then
        ShowHelpOnLoginCheckButton:SetChecked(RCPartyOrbsDB.showHelpOnLogin ~= false)
    end
    if TogglePlayerOrbsButton then
        if RCPartyOrbsDB.showPlayerOrbs ~= false then
            TogglePlayerOrbsButton:SetText("Hide Orbs")
        else
            TogglePlayerOrbsButton:SetText("Show Orbs")
        end
    end
    menuUpdating = false
end

function RCPartyOrbs_IsMenuUpdating()
    return menuUpdating
end

function Handle_RCPartyOrbsGUI()
    if RCPartyOrbsGUI:IsVisible() then
        RCPartyOrbsGUI:Hide()
        PlaySound(830)
        
        -- Also close the test menu
        if RCPartyOrbsTestGUI and RCPartyOrbsTestGUI:IsVisible() then
            RCPartyOrbsTestGUI:Hide()
        end
        
        -- Exit test mode when closing GUI
        if testMode then
            testPartyData = {}
            testMode = false
            
            -- Update button text
            if RCPartyOrbsTestModeButton then
                RCPartyOrbsTestModeButton:SetText("Toggle Test Mode")
            end
            
            RCPartyOrbs_UpdateVisibility()
            UpdateAllOrbs()
            print("RC Party Orbs: Test mode DISABLED")
        end
    else
        RCPartyOrbsGUI:Show()
        PlaySound(829)
        RCPartyOrbs_UpdateMenu()
    end
end

function RCPartyOrbs_SetScale(val)
    if menuUpdating then return end
    RCPartyOrbsDB.scale = (val / 100)
    for _, orb in ipairs(orbFrames) do
        orb:SetScale(RCPartyOrbsDB.scale)
    end
    -- Re-register unit watch to ensure orbs stay visible after scale change
    RCPartyOrbs_UpdateVisibility()
end

function RCPartyOrbs_SetOrbSize(val)
    if menuUpdating then return end
    RCPartyOrbsDB.orbSize = val
    RCPartyOrbs_ApplyOrbSize(val)
end

function RCPartyOrbs_ApplyOrbSize(val)
    local geom = {}
    for i, orb in ipairs(orbFrames) do
        local baseSize = val
        
        -- Target orb and party target orbs use the same scale setting
        if orb.unit == "target" or (orb.unit and orb.unit:match("party%dtarget")) then
            local targetScale = RCPartyOrbsDB.targetOrbScale or 75
            baseSize = val * (targetScale / 100)
        end
        
        local manaSize = baseSize * 1.3  -- Mana orb is 30% bigger
        local healthSize = baseSize
        local fireBorderSize = manaSize * 1.6  -- Fire border 60% larger than mana
        
        -- Resize main container -- PROTECTED, goes through the secure proxy.
        -- Everything below it is an unprotected child frame or region and can
        -- be resized directly at any time, combat or not.
        geom[#geom + 1] = { i, manaSize, manaSize }
        
        -- Resize mana orb and its components
        if orb.manaOrb then
            orb.manaOrb:SetSize(manaSize, manaSize)
            if orb.manaOrb.bg then
                orb.manaOrb.bg:SetSize(manaSize, manaSize)
            end
            if orb.manaOrb.filling then
                orb.manaOrb.filling:SetSize(manaSize - 6, manaSize - 6)
            end
            if orb.manaOrb.gloss then
                orb.manaOrb.gloss:SetSize(manaSize - 4, manaSize - 4)
            end
        end
        
        -- Resize health orb and its components
        if orb.healthOrb then
            orb.healthOrb:SetSize(healthSize, healthSize)
            if orb.healthOrb.bg then
                orb.healthOrb.bg:SetSize(healthSize, healthSize)
            end
            if orb.healthOrb.filling then
                orb.healthOrb.filling:SetSize(healthSize - 6, healthSize - 6)
            end
            if orb.healthOrb.gloss then
                orb.healthOrb.gloss:SetSize(healthSize - 4, healthSize - 4)
            end
            -- Resize galaxies
            local galaxySize = healthSize - 5
            if orb.healthOrb.galaxy1 then
                orb.healthOrb.galaxy1:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy1.texture then
                    orb.healthOrb.galaxy1.texture:SetSize(galaxySize, galaxySize)
                end
            end
            if orb.healthOrb.galaxy2 then
                orb.healthOrb.galaxy2:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy2.texture then
                    orb.healthOrb.galaxy2.texture:SetSize(galaxySize, galaxySize)
                end
            end
            if orb.healthOrb.galaxy3 then
                orb.healthOrb.galaxy3:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy3.texture then
                    orb.healthOrb.galaxy3.texture:SetSize(galaxySize, galaxySize)
                end
            end
        end
        
        -- Resize fire border
        if orb.fireBorder then
            orb.fireBorder:SetSize(fireBorderSize, fireBorderSize)
        end
        
        -- Resize font sizes based on orb size AND user font scale setting
        local orbFontScale = baseSize / 100
        local userFontScale = (RCPartyOrbsDB.fontScale or 100) / 100
        local fontScale = orbFontScale * userFontScale
        
        if orb.healthPct then
            orb.healthPct:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.healthVal then
            orb.healthVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.manaVal then
            orb.manaVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 14 * fontScale, "THINOUTLINE")
        end
        
        -- Resize nameplate
        local nameplateWidth = manaSize  -- Same width as mana orb
        local nameplateHeight = manaSize * 0.25
        if orb.nameplate then
            orb.nameplate:SetSize(nameplateWidth, nameplateHeight)
        end
        if orb.nameplateGlow then
            orb.nameplateGlow:SetSize(nameplateWidth, nameplateHeight)
        end
        if orb.nameText then
            orb.nameText:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 20 * fontScale, "OUTLINE")
        end

        -- Resize fontHolder to cover nameplate area above the container
        if orb.fontHolder then
            local overhang = math.floor((manaSize * 0.35) + 0.5)
            orb.fontHolder:ClearAllPoints()
            orb.fontHolder:SetPoint("TOPLEFT", orb, "TOPLEFT", 0, overhang)
            orb.fontHolder:SetPoint("BOTTOMRIGHT", orb, "BOTTOMRIGHT", 0, 0)
        end

        UpdateOrbHealth(orb)
    end

    -- Push all container sizes through the secure proxy in one batch
    RCPartyOrbs_ApplyGeometry(geom)

    -- Reposition orbs
    PositionOrbs()
end

function RCPartyOrbs_SetOrbSpacing(val)
    if menuUpdating then return end
    RCPartyOrbsDB.orbSpacing = val
    -- Reposition orbs with new spacing
    PositionOrbs()
end

function RCPartyOrbs_SetTargetOrbSpacing(val)
    if menuUpdating then return end
    RCPartyOrbsDB.targetOrbSpacing = val
    -- Reposition orbs with new spacing
    PositionOrbs()
end

function RCPartyOrbs_SetFontScale(val)
    if menuUpdating then return end
    RCPartyOrbsDB.fontScale = val
    
    -- Update all orb fonts
    local baseOrbSize = RCPartyOrbsDB.orbSize or 80
    local orbFontScale = baseOrbSize / 100
    local userFontScale = val / 100
    local fontScale = orbFontScale * userFontScale
    
    for _, orb in ipairs(orbFrames) do
        if orb.healthPct then
            orb.healthPct:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.healthVal then
            orb.healthVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.manaVal then
            orb.manaVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 14 * fontScale, "THINOUTLINE")
        end
        if orb.nameText then
            orb.nameText:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 20 * fontScale, "OUTLINE")
        end
    end
end

function RCPartyOrbs_ApplyTargetOrbSize(scalePercent)
    -- scalePercent is 25-150, representing percentage of normal orb size
    -- Apply to target orb (index 6) and party target orbs (indices 7-10)
    local baseOrbSize = RCPartyOrbsDB.orbSize or 80
    local baseSize = baseOrbSize * (scalePercent / 100)
    
    local manaSize = baseSize * 1.3  -- Mana orb is 30% bigger
    local healthSize = baseSize
    local fireBorderSize = manaSize * 1.6  -- Fire border 60% larger than mana
    
    local geom = {}
    
    -- Helper function to resize a single orb
    local function ResizeTargetOrb(index, orb)
        if not orb then return end
        
        -- Resize main container -- PROTECTED, goes through the secure proxy
        geom[#geom + 1] = { index, manaSize, manaSize }
        
        -- Resize mana orb and its components
        if orb.manaOrb then
            orb.manaOrb:SetSize(manaSize, manaSize)
            if orb.manaOrb.bg then
                orb.manaOrb.bg:SetSize(manaSize, manaSize)
            end
            if orb.manaOrb.filling then
                orb.manaOrb.filling:SetSize(manaSize - 6, manaSize - 6)
            end
            if orb.manaOrb.gloss then
                orb.manaOrb.gloss:SetSize(manaSize - 4, manaSize - 4)
            end
        end
        
        -- Resize health orb and its components
        if orb.healthOrb then
            orb.healthOrb:SetSize(healthSize, healthSize)
            if orb.healthOrb.bg then
                orb.healthOrb.bg:SetSize(healthSize, healthSize)
            end
            if orb.healthOrb.filling then
                orb.healthOrb.filling:SetSize(healthSize - 6, healthSize - 6)
            end
            if orb.healthOrb.gloss then
                orb.healthOrb.gloss:SetSize(healthSize - 4, healthSize - 4)
            end
            -- Resize galaxies
            local galaxySize = healthSize - 5
            if orb.healthOrb.galaxy1 then
                orb.healthOrb.galaxy1:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy1.texture then
                    orb.healthOrb.galaxy1.texture:SetSize(galaxySize, galaxySize)
                end
            end
            if orb.healthOrb.galaxy2 then
                orb.healthOrb.galaxy2:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy2.texture then
                    orb.healthOrb.galaxy2.texture:SetSize(galaxySize, galaxySize)
                end
            end
            if orb.healthOrb.galaxy3 then
                orb.healthOrb.galaxy3:SetSize(galaxySize, galaxySize)
                if orb.healthOrb.galaxy3.texture then
                    orb.healthOrb.galaxy3.texture:SetSize(galaxySize, galaxySize)
                end
            end
        end
        
        -- Resize fire border
        if orb.fireBorder then
            orb.fireBorder:SetSize(fireBorderSize, fireBorderSize)
        end
        
        -- Resize font sizes based on orb size
        local fontScale = baseSize / 100
        if orb.healthPct then
            orb.healthPct:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.healthVal then
            orb.healthVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 18 * fontScale, "THINOUTLINE")
        end
        if orb.manaVal then
            orb.manaVal:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 14 * fontScale, "THINOUTLINE")
        end
        
        -- Resize nameplate
        local nameplateWidth = manaSize
        local nameplateHeight = manaSize * 0.25
        if orb.nameplate then
            orb.nameplate:SetSize(nameplateWidth, nameplateHeight)
        end
        if orb.nameplateGlow then
            orb.nameplateGlow:SetSize(nameplateWidth, nameplateHeight)
        end
        if orb.nameText then
            orb.nameText:SetFont("Interface\\AddOns\\RCPartyOrbs\\fonts\\crash-a-like.ttf", 20 * fontScale, "OUTLINE")
        end
        
        UpdateOrbHealth(orb)
    end
    
    -- Resize target orb (index 6) and party target orbs (indices 7-10)
    for i = 6, 10 do
        ResizeTargetOrb(i, orbFrames[i])
    end
    
    -- Reposition party target orbs since sizes changed
    PositionOrbs()
end

function RCPartyOrbs_ToggleTestMode()
    local debug = RCPartyOrbsDB and RCPartyOrbsDB.debugMode
    if debug then print("ToggleTestMode called, testMode was: " .. tostring(testMode)) end
    
    testMode = not testMode
    if debug then print("testMode is now: " .. tostring(testMode)) end
    
    if testMode then
        -- Create fake data for player and 4 party members
        local classColors = { 
            {0.78, 0.61, 0.43},  -- Warrior (player)
            {0.0, 0.44, 0.87},   -- Shaman (party1)
            {1.0, 1.0, 1.0},     -- Priest (party2)
            {0.67, 0.83, 0.45},  -- Hunter (party3)
            {1.0, 0.49, 0.04}    -- Druid (party4)
        }
        local names = {"Player", "Shaman", "Priest", "Hunter", "Druid"}
        local units = {"player", "party1", "party2", "party3", "party4"}
        
        for i = 1, 5 do
            testPartyData[units[i]] = { 
                h = math.random(3000, 10000), maxH = 10000, 
                p = math.random(1000, 5000), maxP = 5000, 
                name = names[i], 
                r = classColors[i][1], g = classColors[i][2], b = classColors[i][3] 
            }
        end
        
        -- Add target data (enemy style - red)
        testPartyData["target"] = { 
            h = math.random(5000, 15000), maxH = 15000, 
            p = math.random(2000, 8000), maxP = 8000, 
            name = "Target Mob", r = 0.9, g = 0.1, b = 0.1 
        }
        
        -- Add party target data (what each party member is targeting)
        local targetNames = {"Grunt", "Peon", "Overseer", "Warlock"}
        for i = 1, 4 do
            testPartyData["party" .. i .. "target"] = {
                h = math.random(2000, 8000), maxH = 8000,
                p = math.random(1000, 4000), maxP = 4000,
                name = targetNames[i], r = 0.8, g = 0.2, b = 0.2
            }
        end
        
        if RCPartyOrbsTestModeButton then
            RCPartyOrbsTestModeButton:SetText("Exit Test")
        end
        
        -- UNREGISTER unit watch so it doesn't hide our test orbs
        for i = 2, 10 do
            if orbFrames[i] then
                UnregisterUnitWatch(orbFrames[i])
            end
        end
        
        -- Force show ALL orbs including party, target, and party targets
        for i = 1, 10 do
            if orbFrames[i] then
                orbFrames[i]:Show()
                orbFrames[i]:SetAlpha(1.0)
            end
        end
        
        -- Show fire borders with different threat colors for testing
        -- Player (index 1) - RED (high threat/tanking)
        if orbFrames[1] and orbFrames[1].fireBorder then
            orbFrames[1].fireBorder:Show()
            orbFrames[1].fireBorder:SetVertexColor(1, 0, 0, 1)
        end
        
        -- Shaman/Party1 (index 2) - YELLOW (medium threat)
        if orbFrames[2] and orbFrames[2].fireBorder then
            orbFrames[2].fireBorder:Show()
            orbFrames[2].fireBorder:SetVertexColor(1, 1, 0, 1)
        end
        
        -- Priest/Party2 (index 3) - YELLOW (medium threat)
        if orbFrames[3] and orbFrames[3].fireBorder then
            orbFrames[3].fireBorder:Show()
            orbFrames[3].fireBorder:SetVertexColor(1, 1, 0, 1)
        end
        
        -- Hunter/Party3 (index 4) - YELLOW (medium threat)
        if orbFrames[4] and orbFrames[4].fireBorder then
            orbFrames[4].fireBorder:Show()
            orbFrames[4].fireBorder:SetVertexColor(1, 1, 0, 1)
        end
        
        -- Druid/Party4 (index 5) - GREEN (low threat)
        if orbFrames[5] and orbFrames[5].fireBorder then
            orbFrames[5].fireBorder:Show()
            orbFrames[5].fireBorder:SetVertexColor(0, 1, 0, 0.7)
        end
        
        -- Target (index 6) - no threat border
        if orbFrames[6] and orbFrames[6].fireBorder then
            orbFrames[6].fireBorder:Hide()
        end
        
        -- Position orbs properly
        PositionOrbs()
        
        -- Update all orbs with test data
        UpdateAllOrbs()
        
        print("RC Party Orbs: Test mode ENABLED - showing fake party")
    else
        testPartyData = {}
        testMode = false
        
        if RCPartyOrbsTestModeButton then
            RCPartyOrbsTestModeButton:SetText("Toggle Test Mode")
        end
        
        -- Hide fire borders
        for i = 1, 10 do
            if orbFrames[i] and orbFrames[i].fireBorder then
                orbFrames[i].fireBorder:Hide()
            end
        end
        
        RCPartyOrbs_UpdateVisibility()
        UpdateAllOrbs()
        
        print("RC Party Orbs: Test mode DISABLED")
    end
end

-- Toggle orientation between vertical and horizontal
function RCPartyOrbs_ToggleLayoutOrientation()
    if RCPartyOrbsDB.partyOrientation == "vertical" then
        RCPartyOrbsDB.partyOrientation = "horizontal"
        print("RC Party Orbs: Layout set to HORIZONTAL")
    else
        RCPartyOrbsDB.partyOrientation = "vertical"
        print("RC Party Orbs: Layout set to VERTICAL")
    end
    
    PositionOrbs()
    
    -- Update button text if it exists
    if RCPartyOrbsOrientationButton then
        if RCPartyOrbsDB.partyOrientation == "vertical" then
            RCPartyOrbsOrientationButton:SetText("Layout: Vertical")
        else
            RCPartyOrbsOrientationButton:SetText("Layout: Horizontal")
        end
    end
end

function RCPartyOrbs_ResetPositions()
    if not isDragging then
        -- Clear saved positions
        RCPartyOrbsDB.orbPositions = {}
        RCPartyOrbsDB.lastOrbPositions = {}
        RCPartyOrbs_RepositionOrbs()
        print("RC Party Orbs: Positions reset to default")
    end
end

-- Undo last move
function RCPartyOrbs_UndoLastMove()
    if RCPartyOrbsDB.lastOrbPositions then
        -- Swap current and last positions
        local currentPositions = {}
        for i = 1, 6 do
            if orbFrames[i] then
                local unit = orbFrames[i].unit
                local point, relativeTo, relativePoint, xOfs, yOfs = orbFrames[i]:GetPoint()
                currentPositions[unit] = {
                    point = point,
                    relativeTo = relativeTo and relativeTo:GetName() or "UIParent",
                    relativePoint = relativePoint,
                    x = xOfs,
                    y = yOfs
                }
            end
        end
        
        -- Restore last positions (via the secure proxy - containers are protected)
        local undoGeom = {}
        for i = 1, 6 do
            if orbFrames[i] then
                local unit = orbFrames[i].unit
                if RCPartyOrbsDB.lastOrbPositions[unit] then
                    local pos = RCPartyOrbsDB.lastOrbPositions[unit]
                    undoGeom[#undoGeom + 1] = { i, 0, 0, pos.point,
                                                RCPartyOrbs_RelIndex(pos.relativeTo),
                                                pos.relativePoint, pos.x, pos.y }
                    
                    -- Update saved positions
                    if not RCPartyOrbsDB.orbPositions then RCPartyOrbsDB.orbPositions = {} end
                    RCPartyOrbsDB.orbPositions[unit] = pos
                end
            end
        end
        
        RCPartyOrbs_ApplyGeometry(undoGeom)
        
        -- Store current as last (so you can redo)
        RCPartyOrbsDB.lastOrbPositions = currentPositions
        
        print("RC Party Orbs: Undo - Restored previous positions")
    else
        print("RC Party Orbs: Nothing to undo")
    end
end

-- Toggle frame lock/unlock
function RCPartyOrbs_ToggleFrameLock()
    if InCombatLockdown() then
        print("|cFFFF0000RCPartyOrbs:|r Cannot toggle frame lock during combat.")
        return
    end
    
    RCPartyOrbsDB.framesLocked = not RCPartyOrbsDB.framesLocked

    -- Ensure orb is fully built at correct size whenever lock state changes
    if RCPartyOrbsDB then
        local savedSize = RCPartyOrbsDB.orbSize or 80
        RCPartyOrbs_ApplyOrbSize(savedSize)
    end
    -- Register/unregister drag on all orb frames to avoid click/drag race during combat
    for _, orb in ipairs(orbFrames) do
        if orb then
            if RCPartyOrbsDB.framesLocked then
                orb:RegisterForDrag()  -- No args = unregister all drag buttons
            else
                orb:RegisterForDrag("LeftButton")
            end
        end
    end
    
    if RCPartyOrbsDB.framesLocked then
        print("RC Party Orbs: Frames LOCKED")
    else
        print("RC Party Orbs: Frames UNLOCKED - Drag orbs to reposition")
    end
    
    -- Update button text
    if LockFramesButton then
        if RCPartyOrbsDB.framesLocked then
            LockFramesButton:SetText("Unlock Frames")
        else
            LockFramesButton:SetText("Lock Frames")
        end
    end
end


-----------------------------------------------------------
-- 9. MINIMAP BUTTON LOGIC
-----------------------------------------------------------


-----------------------------------------------------------
-- 9.5 CAST BAR FUNCTIONS
-----------------------------------------------------------

-- Find the orb for a given unit
local function GetOrbForUnit(unit)
    for _, orb in ipairs(orbFrames) do
        if orb.unit == unit then
            return orb
        end
    end
    return nil
end

-- Handle cast start
function RCPartyOrbs_OnCastStart(unit, isChannel)
    -- Check if cast bars are enabled
    if RCPartyOrbsDB.showCastBars == false then return end
    
    local orb = GetOrbForUnit(unit)
    if not orb or not orb.castBar then return end
    
    local name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID
    
    if isChannel then
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, notInterruptible, spellID = UnitChannelInfo(unit)
    else
        name, text, texture, startTimeMS, endTimeMS, isTradeSkill, castID, notInterruptible, spellID = UnitCastingInfo(unit)
    end
    
    if not name then return end
    
    local castBar = orb.castBar
    castBar.casting = not isChannel
    castBar.channeling = isChannel
    castBar.startTime = startTimeMS / 1000
    castBar.endTime = endTimeMS / 1000
    castBar.spellID = spellID
    
    -- Set spell name
    castBar.spellName:SetText(name)
    
    -- Set cast bar color based on interruptible
    if notInterruptible then
        castBar.activeColor = {0.6, 0.6, 0.6}  -- Grey for non-interruptible
    else
        castBar.activeColor = {1, 0.9, 0.3}  -- Bright gold for interruptible
    end
    
    -- Set initial progress
    if isChannel then
        castBar:UpdateProgress(1)
    else
        castBar:UpdateProgress(0)
    end
    
    castBar:Show()
end

-- Handle cast stop
function RCPartyOrbs_OnCastStop(unit)
    local orb = GetOrbForUnit(unit)
    if not orb or not orb.castBar then return end
    
    orb.castBar.casting = false
    orb.castBar.channeling = false
    orb.castBar:Hide()
end

-- Handle channel update (for channeled spells that change duration)
function RCPartyOrbs_OnChannelUpdate(unit)
    local orb = GetOrbForUnit(unit)
    if not orb or not orb.castBar then return end
    if not orb.castBar.channeling then return end
    
    local name, text, texture, startTimeMS, endTimeMS = UnitChannelInfo(unit)
    if name then
        orb.castBar.startTime = startTimeMS / 1000
        orb.castBar.endTime = endTimeMS / 1000
    end
end

-----------------------------------------------------------
-- 10. EVENT ENGINE-- PARTY FRAME INITIALIZATION REMOVED
-----------------------------------------------------------

local frame = RCPartyOrbs_EventFrame
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("UNIT_HEALTH")
frame:RegisterEvent("UNIT_MAXHEALTH")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
frame:RegisterEvent("PLAYER_TARGET_CHANGED")
frame:RegisterEvent("UNIT_TARGET")
frame:RegisterEvent("UNIT_AURA")    -- For debuff tracking
frame:RegisterEvent("PLAYER_REGEN_ENABLED")
frame:RegisterEvent("NAME_PLATE_UNIT_ADDED")
frame:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
frame:RegisterEvent("PLAYER_REGEN_DISABLED")
frame:RegisterEvent("SPELLS_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
-- Cast bar events
frame:RegisterEvent("UNIT_SPELLCAST_START")
frame:RegisterEvent("UNIT_SPELLCAST_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
frame:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
frame:RegisterEvent("UNIT_FLAGS")
frame:RegisterEvent("UNIT_PET")    -- For Warlock Felhunter summon/dismiss (purge availability)
frame:RegisterEvent("UNIT_NAME_UPDATE")

-- Define the full init function that PLAYER_ENTERING_WORLD calls
function RCPartyOrbs_FullInit()
    if not RCPartyOrbsDB then return end
    if RCPartyOrbsDB.showName == nil then RCPartyOrbsDB.showName = true end
    if RCPartyOrbsDB.showHealthPercentage == nil then RCPartyOrbsDB.showHealthPercentage = true end
    if RCPartyOrbsDB.showHealthValue == nil then RCPartyOrbsDB.showHealthValue = true end
    if RCPartyOrbsDB.showManaValue == nil then RCPartyOrbsDB.showManaValue = true end
    if RCPartyOrbsDB.minimapButtonAngle then
        RCPartyOrbsMiniMapButtonPosition.locationAngle = RCPartyOrbsDB.minimapButtonAngle
    end
    RCPartyOrbsMiniMapButton_Reposition()
    if RCPartyOrbsSizeSlider then
        RCPartyOrbsSizeSlider:SetValue(RCPartyOrbsDB.orbSize or 80)
    else
        RCPartyOrbs_ApplyOrbSize(RCPartyOrbsDB.orbSize or 80)
    end
    RCPartyOrbs_UpdateVisibility()
    UpdateAllOrbs()
end

frame:SetScript("OnEvent", function(self, event, arg1)
        if event == "ADDON_LOADED" and arg1 == "RCPartyOrbs" then
        -- NOTE: SavedVariables are NOT loaded yet at ADDON_LOADED.
        -- DB sanitization and position restore happen in VARIABLES_LOADED below.
        
        -- Early disable of Blizzard party frames to prevent errors
        -- This fixes the UnitFrameManaCostPredictionBars_Update nil error in raids
        RCPartyOrbs_HideBlizzardFrames()

        print("RC Party Orbs Initialized. Type /fpo for settings.")

    elseif event == "VARIABLES_LOADED" then
                -- SavedVariables are now guaranteed to be populated.
        -- STARTUP SANITIZATION
        RCPartyOrbsDB = RCPartyOrbsDB or {}
        for k, v in pairs(DB_DEFAULTS) do
            if RCPartyOrbsDB[k] == nil then RCPartyOrbsDB[k] = v end
        end

        -- v75→v76 migration: upgrade stale spacing defaults from old installs.
        if not RCPartyOrbsDB.dbVersion or RCPartyOrbsDB.dbVersion < 76 then
            if RCPartyOrbsDB.orbSpacing == 15 then
                RCPartyOrbsDB.orbSpacing = 20
            end
            if RCPartyOrbsDB.targetOrbSpacing == 5 then
                RCPartyOrbsDB.targetOrbSpacing = 15
            end
            RCPartyOrbsDB.dbVersion = 76
        end

        currentSwirlSet = RCPartyOrbsDB.swirlSet or "bubbles"

        -- Scale menus to 75%
        if RCPartyOrbsGUI then RCPartyOrbsGUI:SetScale(0.75) end
        if RCPartyOrbsTestGUI then RCPartyOrbsTestGUI:SetScale(0.75) end

        -- Load saved minimap angle now that DB is ready, then reposition
        if RCPartyOrbsDB.minimapButtonAngle then
            RCPartyOrbsMiniMapButtonPosition.locationAngle = RCPartyOrbsDB.minimapButtonAngle
        end
        C_Timer.After(0.1, function()
            RCPartyOrbsMiniMapButton_Reposition()
        end)

    elseif event == "PLAYER_LOGIN" then
                -- Initialize character-specific colors
        InitializeCharacterColors()

        -- Initialize dispel detection
        UpdatePlayerDispels()

        -- Show help menu on login if enabled
        Compat.After(2.0, function()
            if RCPartyOrbsDB.showHelpOnLogin and RCPartyOrbsHelpGUI then
                RCPartyOrbsHelpGUI:Show()
            end
        end)

    elseif event == "PLAYER_ENTERING_WORLD" then
                if not RCPartyOrbs_initialized then
            RCPartyOrbs_initialized = true
            RCPartyOrbsDB = RCPartyOrbsDB or {}
            for k, v in pairs(DB_DEFAULTS) do
                if RCPartyOrbsDB[k] == nil then RCPartyOrbsDB[k] = v end
            end
        end
        C_Timer.After(0.5, RCPartyOrbs_FullInit)
        C_Timer.After(2.0, RCPartyOrbs_FullInit)
    elseif event == "GROUP_ROSTER_UPDATE" then
        RCPartyOrbs_UpdateVisibility()
        -- Party frames may re-show after roster update
        Compat.After(0.3, function()
            RCPartyOrbs_UpdateVisibility()
        end)
    elseif event == "PLAYER_TARGET_CHANGED" then
        -- Target changed, update visibility and orbs
        RCPartyOrbs_UpdateVisibility()
        UpdateAllOrbs()  -- Update target orb
    elseif event == "UNIT_TARGET" then
        -- A unit changed their target - update visibility for party target orbs
        -- arg1 is the unit that changed targets (e.g., "party1", "party2", etc.)
        if arg1 and arg1:match("^party%d$") then
            RCPartyOrbs_UpdateVisibility()
        end
    elseif event == "UNIT_AURA" then
        -- Debuff changed, update the specific orb for debuff colors
        -- arg1 is the unit that had aura change
        if arg1 and RCPartyOrbsDB.showDebuffColors then
            -- Find the orb for this unit and update it
            for _, orb in ipairs(orbFrames) do
                if orb.unit == arg1 then
                    UpdateOrbDebuffColor(orb)
                    break
                end
            end
        end
    elseif event == "SPELLS_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
        -- Player's spells changed, update what they can dispel
        Compat.After(0.5, function()
            UpdatePlayerDispels()
            UpdateAllOrbs()
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat ended, process any queued visibility updates
        if pendingVisibilityUpdate then
            pendingVisibilityUpdate = false
            RCPartyOrbs_UpdateVisibility()
        end
    elseif event == "NAME_PLATE_UNIT_ADDED" or event == "NAME_PLATE_UNIT_REMOVED" then
        -- Nameplate added/removed, update threat for all orbs
        -- (threat will be recalculated in UpdateAllOrbs)
    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Combat started, threat updates will happen via other events
    elseif event == "UNIT_FLAGS" then
        -- Unit flags changed (includes death/alive state)
        -- Immediately update the orb for this unit
        if arg1 then
            for _, orb in ipairs(orbFrames) do
                if orb.unit == arg1 then
                    UpdateOrbHealth(orb)
                    break
                end
            end
        end
    elseif event == "UNIT_PET" and arg1 == "player" then
        -- Player's pet changed (e.g. Warlock summoned/dismissed Felhunter).
        -- Re-evaluate all orb debuff/purgeable colors so the highlight and sound
        -- correctly reflect whether Devour Magic is now available or not.
        -- Clear hasDebuffColor on the target orb so the sound can fire fresh if
        -- the Felhunter is summoned while a purgeable buff is already on the target.
        if orbFrames[6] then
            orbFrames[6].hasDebuffColor = nil
        end
        UpdateAllOrbs()
    elseif event == "UNIT_NAME_UPDATE" then
        -- Name became available (e.g. player name ready after login, or party member name resolved)
        -- Just trigger an orb update for that unit so the nameplate gets populated
        if arg1 == "player" and orbFrames[1] then
            UpdateOrbHealth(orbFrames[1])
        else
            for i = 1, 4 do
                if orbFrames[i+1] and orbFrames[i+1].unit == arg1 then
                    UpdateOrbHealth(orbFrames[i+1])
                    break
                end
            end
        end
    -- Cast bar events
    elseif event == "UNIT_SPELLCAST_START" then
        RCPartyOrbs_OnCastStart(arg1, false)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        RCPartyOrbs_OnCastStart(arg1, true)
    elseif event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_FAILED" or 
           event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
        RCPartyOrbs_OnCastStop(arg1)
    elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        RCPartyOrbs_OnChannelUpdate(arg1)
    end
    -- PERFORMANCE: UpdateAllOrbs now only processes visible orbs (see function definition)
    UpdateAllOrbs()
end)

-- Animation Engine (Swirls and Fire Borders)
local animFrame = CreateFrame("Frame")
animFrame:SetScript("OnUpdate", function(self, delta)
    -- PERFORMANCE: Only process orbs that are actually shown
    -- In raids, most orbs are hidden, so we skip them entirely
    for _, orb in ipairs(orbFrames) do
        if orb and orb:IsShown() then
            -- Galaxies rotate automatically via AnimationGroup created in CreateGalaxy
            -- No manual rotation needed
            
            -- Animate fire border (uses frames 01-29)
            -- PERFORMANCE: Check if fire border exists AND is shown before processing
            if orb.fireBorder and orb.fireBorder:IsShown() then
                orb.fireElapsed = (orb.fireElapsed or 0) + delta
                if orb.fireElapsed >= FRAME_RATE then
                    orb.fireElapsed = 0
                    orb.fireCurrentFrame = ((orb.fireCurrentFrame or 0) % FRAME_COUNT) + 1
                    local path = string.format("Interface\\AddOns\\RCPartyOrbs\\images\\fire_frame_%02d.tga", orb.fireCurrentFrame)
                    orb.fireBorder:SetTexture(path)
                end
            end
        end
    end
end)

-----------------------------------------------------------
-- 10. COLOR PICKER FUNCTION
-----------------------------------------------------------

function RCPartyOrbs_OpenColorPicker(colorType)
    -- Open color picker for different colors
    local currentColor
    local colorInfo
    local _, playerClass = UnitClass("player")
    
    if colorType == "fire" then
        currentColor = RCPartyOrbsDB.fireBorderColor or {r=1, g=0, b=0, a=1}
        colorInfo = "Fire Border (Red Threat)"
    elseif colorType == "green" then
        currentColor = RCPartyOrbsDB.greenBorderColor or {r=0, g=1, b=0, a=1}
        colorInfo = "Green Border (Low Threat)"
    elseif colorType == "yellow" then
        currentColor = RCPartyOrbsDB.yellowBorderColor or {r=1, g=1, b=0, a=1}
        colorInfo = "Yellow Border (Medium Threat)"
    elseif colorType == "health" then
        currentColor = GetCharacterColor("healthColor") or GetDefaultColor("health", playerClass)
        colorInfo = "Health Orb"
    elseif colorType == "mana" then
        currentColor = GetCharacterColor("manaColor") or GetDefaultColor("mana", playerClass)
        colorInfo = "Mana Orb"
    elseif colorType == "rage" then
        currentColor = GetCharacterColor("rageColor") or GetDefaultColor("rage", playerClass)
        colorInfo = "Rage"
    elseif colorType == "energy" then
        currentColor = GetCharacterColor("energyColor") or GetDefaultColor("energy", playerClass)
        colorInfo = "Energy"
    elseif colorType == "focus" then
        currentColor = GetCharacterColor("focusColor") or GetDefaultColor("focus", playerClass)
        colorInfo = "Focus"
    elseif colorType == "runic" then
        currentColor = GetCharacterColor("runicColor") or GetDefaultColor("runic", playerClass)
        colorInfo = "Runic Power"
    elseif colorType == "chi" then
        currentColor = GetCharacterColor("chiColor") or GetDefaultColor("chi", playerClass)
        colorInfo = "Chi (Monk)"
    else
        return
    end
    
    -- Store the color type in the frame so it persists in callbacks
    ColorPickerFrame.rcPartyOrbsColorType = colorType
    
    -- Callback to apply any color change (called during picker interaction and on OK)
    local function applyFunc()
        local r, g, b, a
        if RCPartyOrbs_Version.isRetail then
            -- Dragonflight+ passes r,g,b as args; opacity via ColorPickerFrame
            r, g, b = ColorPickerFrame:GetColorRGB()
            local opacity = ColorPickerFrame:GetColorAlpha()
            a = opacity ~= nil and opacity or 1
        else
            r, g, b = ColorPickerFrame:GetColorRGB()
            a = 1
            if OpacitySliderFrame and OpacitySliderFrame:GetValue() then
                a = 1 - OpacitySliderFrame:GetValue()
            end
        end
        local cType = ColorPickerFrame.rcPartyOrbsColorType
        
        -- Update the appropriate color in database
        if cType == "fire" then
            RCPartyOrbsDB.fireBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[1] and orbFrames[1].fireBorder then
                orbFrames[1].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "green" then
            RCPartyOrbsDB.greenBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[5] and orbFrames[5].fireBorder then
                orbFrames[5].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "yellow" then
            RCPartyOrbsDB.yellowBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[2] and orbFrames[2].fireBorder then
                orbFrames[2].fireBorder:SetVertexColor(r, g, b, a)
            end
            if orbFrames[3] and orbFrames[3].fireBorder then
                orbFrames[3].fireBorder:SetVertexColor(r, g, b, a)
            end
            if orbFrames[4] and orbFrames[4].fireBorder then
                orbFrames[4].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "health" then
            SetCharacterColor("healthColor", {r=r, g=g, b=b, a=a})
        elseif cType == "mana" then
            SetCharacterColor("manaColor", {r=r, g=g, b=b, a=a})
        elseif cType == "rage" then
            SetCharacterColor("rageColor", {r=r, g=g, b=b, a=a})
        elseif cType == "energy" then
            SetCharacterColor("energyColor", {r=r, g=g, b=b, a=a})
        elseif cType == "focus" then
            SetCharacterColor("focusColor", {r=r, g=g, b=b, a=a})
        elseif cType == "runic" then
            SetCharacterColor("runicColor", {r=r, g=g, b=b, a=a})
        elseif cType == "chi" then
            SetCharacterColor("chiColor", {r=r, g=g, b=b, a=a})
        end
        
        -- Apply the color to all relevant elements
        for _, orb in ipairs(orbFrames) do
            if cType == "health" then
                -- Update health orb filling and galaxies
                if orb.healthOrb and orb.healthOrb.filling then
                    orb.healthOrb.filling:SetVertexColor(r, g, b, a)
                end
                if orb.healthOrb and orb.healthOrb.galaxy1 then
                    orb.healthOrb.galaxy1.texture:SetVertexColor(r, g, b, 1)
                end
                if orb.healthOrb and orb.healthOrb.galaxy2 then
                    orb.healthOrb.galaxy2.texture:SetVertexColor(r, g, b, 1)
                end
                if orb.healthOrb and orb.healthOrb.galaxy3 then
                    orb.healthOrb.galaxy3.texture:SetVertexColor(r, g, b, 1)
                end
            elseif cType == "mana" or cType == "rage" or cType == "energy" or cType == "focus" or cType == "runic" or cType == "chi" then
                -- Update mana/power orb filling and gloss
                if orb.manaOrb and orb.manaOrb.filling then
                    orb.manaOrb.filling:SetVertexColor(r, g, b, a)
                end
                if orb.manaOrb and orb.manaOrb.bg then
                    orb.manaOrb.bg:SetVertexColor(r * 0.5 + 0.2, g * 0.5 + 0.2, b * 0.5 + 0.2, 0.7)
                end
            end
        end
        
        -- Force a full refresh of all orbs to apply the new colors
        if RCPartyOrbs_ForceUpdateAllOrbs then
            RCPartyOrbs_ForceUpdateAllOrbs()
        end
    end
    
    -- Cancel function: restore previous color
    local function cancelFunc()
        local r = ColorPickerFrame.previousValues.r
        local g = ColorPickerFrame.previousValues.g
        local b = ColorPickerFrame.previousValues.b
        local a = ColorPickerFrame.previousValues.a
        local cType = ColorPickerFrame.rcPartyOrbsColorType
        
        -- Restore previous color
        if cType == "fire" then
            RCPartyOrbsDB.fireBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[1] and orbFrames[1].fireBorder then
                orbFrames[1].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "green" then
            RCPartyOrbsDB.greenBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[5] and orbFrames[5].fireBorder then
                orbFrames[5].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "yellow" then
            RCPartyOrbsDB.yellowBorderColor = {r=r, g=g, b=b, a=a}
            if orbFrames[2] and orbFrames[2].fireBorder then
                orbFrames[2].fireBorder:SetVertexColor(r, g, b, a)
            end
            if orbFrames[3] and orbFrames[3].fireBorder then
                orbFrames[3].fireBorder:SetVertexColor(r, g, b, a)
            end
            if orbFrames[4] and orbFrames[4].fireBorder then
                orbFrames[4].fireBorder:SetVertexColor(r, g, b, a)
            end
        elseif cType == "health" then
            SetCharacterColor("healthColor", {r=r, g=g, b=b, a=a})
        elseif cType == "mana" then
            SetCharacterColor("manaColor", {r=r, g=g, b=b, a=a})
        end
        
        -- Apply the restored color to health/mana
        for _, orb in ipairs(orbFrames) do
            if cType == "health" then
                if orb.healthOrb and orb.healthOrb.filling then
                    orb.healthOrb.filling:SetVertexColor(r, g, b, a)
                end
                if orb.healthOrb and orb.healthOrb.galaxy1 then
                    orb.healthOrb.galaxy1.texture:SetVertexColor(r, g, b, 1)
                end
                if orb.healthOrb and orb.healthOrb.galaxy2 then
                    orb.healthOrb.galaxy2.texture:SetVertexColor(r, g, b, 1)
                end
                if orb.healthOrb and orb.healthOrb.galaxy3 then
                    orb.healthOrb.galaxy3.texture:SetVertexColor(r, g, b, 1)
                end
            elseif cType == "mana" then
                if orb.manaOrb and orb.manaOrb.filling then
                    orb.manaOrb.filling:SetVertexColor(r, g, b, a)
                end
                if orb.manaOrb and orb.manaOrb.bg then
                    orb.manaOrb.bg:SetVertexColor(r * 0.5 + 0.2, g * 0.5 + 0.2, b * 0.5 + 0.2, 0.7)
                end
            end
        end
        
        -- Force a full refresh of all orbs to restore the colors
        if RCPartyOrbs_ForceUpdateAllOrbs then
            RCPartyOrbs_ForceUpdateAllOrbs()
        end
    end
    
    -- Open the color picker using the compatibility wrapper
    Compat.OpenColorPicker({
        r = currentColor.r,
        g = currentColor.g,
        b = currentColor.b,
        a = currentColor.a or 1,
        hasOpacity = true,
        previousValues = { r = currentColor.r, g = currentColor.g, b = currentColor.b, a = currentColor.a or 1 },
        func = applyFunc,
        cancelFunc = cancelFunc,
    })
end

function RCPartyOrbs_OpenTestMenu()
    -- Open the test menu
    RCPartyOrbsTestGUI:Show()
    PlaySound(829)
    
    -- Update the test menu state
    if RCPartyOrbsTestGUI:IsVisible() then
        -- Update button text based on test mode state
        if testMode then
            RCPartyOrbsTestModeButton:SetText("Exit Test")
        else
            RCPartyOrbsTestModeButton:SetText("Toggle Test Mode")
        end
    end
end

function RCPartyOrbs_OpenVisibilityMenu()
    -- Close other sub-menus first
    if RCPartyOrbsOrbColorsGUI then RCPartyOrbsOrbColorsGUI:Hide() end
    if RCPartyOrbsThreatColorsGUI then RCPartyOrbsThreatColorsGUI:Hide() end
    
    -- Open the visibility menu
    if RCPartyOrbsVisibilityGUI then
        if RCPartyOrbsVisibilityGUI:IsShown() then
            RCPartyOrbsVisibilityGUI:Hide()
        else
            RCPartyOrbsVisibilityGUI:Show()
            PlaySound(829)
        end
    end
end

function RCPartyOrbs_OpenHelpMenu()
    -- Open the help menu
    if RCPartyOrbsHelpGUI then
        RCPartyOrbsHelpGUI:Show()
        PlaySound(829)
    end
end

function RCPartyOrbs_PopulateHelpText()
    if not RCPartyOrbsHelpText then return end
    
    local _, playerClass = UnitClass("player")
    local dispelSpell = CLASS_DISPEL_SPELLS[playerClass] or "None"
    local purgeSpell = CLASS_PURGE_SPELLS[playerClass] or "None"
    local rezData = CLASS_REZ_SPELLS[playerClass]
    local combatRez = (rezData and rezData.combat) or "None"
    
    -- Get current modifier key setting
    local modifierNames = {
        ["shift"] = "Shift",
        ["alt"] = "Alt",
        ["ctrl"] = "Ctrl"
    }
    local currentMod = RCPartyOrbsDB.clickModifier or "shift"
    local modifierDisplay = modifierNames[currentMod] or "Shift"
    
    -- Get actual dispel types from playerDispelList
    local canDispelList = ""
    for dispelType, _ in pairs(playerDispelList) do
        if canDispelList ~= "" then canDispelList = canDispelList .. ", " end
        canDispelList = canDispelList .. dispelType
    end
    if canDispelList == "" then canDispelList = "None (check /fpo dispelcheck)" end
    
    local helpText = [[|cFFFFD700RC Party Orbs|r
Diablo-style health & mana orbs for you and your party.

|cFF00FF00== FEATURES ==|r

|cFFFFFF00Orb Display:|r
• Health orb (inner) shows HP with class color
• Mana orb (outer ring) shows power
• Animated swirl effects inside orbs
• Nameplate shows unit name above orb

|cFFFFFF00Threat Borders:|r
• |cFF00FF00Green|r - Low threat (50-74%)
• |cFFFFFF00Yellow|r - Medium threat (75-99%)
• |cFFFF0000Red|r - High threat / Tanking (100%)

|cFF00FF00== DEBUFF COLORS ==|r

When a party member has a dispellable debuff:
• |cFF00CC00Poison|r - Green orb
• |cFF996600Disease|r - Brown orb
• |cFF9900CCCurse|r - Purple orb
• |cFF3399FFMagic|r - Blue orb

|cFF00FF00== ENEMY BUFFS ==|r

When your target (enemy) has a purgeable buff:
• |cFFFFCC33Stealable/Purgeable|r - Gold orb

|cFF00FF00== CLICK ACTIONS ==|r

|cFFFFFF00Left-click|r on any orb:
• Targets the unit

|cFFFFFF00]] .. modifierDisplay .. [[+Left-click|r on party orb (alive):
• Casts your dispel spell

|cFFFFFF00]] .. modifierDisplay .. [[+Left-click|r on party orb (dead, in combat):
• Casts your battle rez

|cFFFFFF00]] .. modifierDisplay .. [[+Left-click|r on target orb (enemy):
• Casts your purge spell

|cFFFFFF00Right-click|r on any orb:
• Opens unit menu (invite, whisper, etc.)

|cFF00FF00== YOUR CLASS INFO ==|r

Class: |cFFFFFF00]] .. (playerClass or "Unknown") .. [[|r
Dispel: |cFFFFFF00]] .. dispelSpell .. [[|r
Battle Rez: |cFFFFFF00]] .. combatRez .. [[|r
Can Dispel: |cFFFFFF00]] .. canDispelList .. [[|r

|cFF00FF00== MOVING ORBS ==|r

|cFFFFFF001.|r Open menu with |cFFFFFF00/fpo|r
|cFFFFFF002.|r Click |cFFFFFF00"Unlock Frames"|r button
|cFFFFFF003.|r Drag any orb to move ALL orbs together
|cFFFFFF004.|r |cFFFFFF00Shift+Drag|r to move a single orb individually
|cFFFFFF005.|r Click |cFFFFFF00"Lock Frames"|r when done
|cFFFFFF006.|r Use |cFFFFFF00"Undo Move"|r if you make a mistake
|cFFFFFF007.|r Use |cFFFFFF00"Reset Positions"|r to restore defaults

|cFF00FF00== SLASH COMMANDS ==|r

|cFFFFFF00/fpo|r - Open settings menu
|cFFFFFF00/fpo test|r - Toggle test mode (show fake party)
|cFFFFFF00/fpo debuff|r - Cycle debuff color test
|cFFFFFF00/fpo debuffoff|r - Turn off debuff test
|cFFFFFF00/fpo dispelcheck|r - Show what you can dispel
|cFFFFFF00/fpo debug|r - Toggle debug mode
|cFFFFFF00/fpo reset|r - Reset orb positions
|cFFFFFF00/fpo toggle|r - Enable/disable addon (reloads UI)

|cFF00FF00== MENU OPTIONS ==|r

• |cFFFFFF00Swirl Type|r - Change orb interior animation
• |cFFFFFF00Orb Size|r - Adjust size of all orbs
• |cFFFFFF00Layout|r - Horizontal or Vertical party arrangement
• |cFFFFFF00Show Name/Health %/Values|r - Toggle text displays
• |cFFFFFF00Show Threat Borders|r - Toggle fire border on threat
• |cFFFFFF00Show Debuff Colors|r - Toggle dispel color indicators
• |cFFFFFF00Font Size|r - Adjust text size (50%-200%)
• |cFFFFFF00Hide/Show Orbs|r - Toggle orb visibility
• |cFFFFFF00Advanced|r - Color pickers, test mode, and more

|cFF00FF00== ADVANCED MENU ==|r

• |cFFFFFF00Toggle Test Mode|r - Show fake party to preview
• |cFFFFFF00Layout|r - Switch Horizontal/Vertical arrangement
• |cFFFFFF00Health/Mana/Border Colors|r - Customize colors
• |cFFFFFF00Target Orb Size|r - Scale target orbs (25%-150%)
• |cFFFFFF00Dispel/Rez Modifier|r - Choose modifier key (Shift/Alt/Ctrl)
• |cFFFFFF00Orb Visibility...|r - Show/hide individual orbs

|cFF00FF00== YOUR SETTINGS ==|r

Current Modifier: |cFFFFFF00]] .. modifierDisplay .. [[+Click|r to Dispel/Rez
]]

    RCPartyOrbsHelpText:SetText(helpText)
end

-----------------------------------------------------------
-- 11. SLASH COMMANDS
-----------------------------------------------------------

SLASH_FIREPARTYORBS1 = "/fpo"
SLASH_FIREPARTYORBS2 = "/firepartyorbs"
SlashCmdList["FIREPARTYORBS"] = function(msg)
    local cmd = msg:lower()
    
    if cmd == "test" then 
        RCPartyOrbs_ToggleTestMode()
    elseif cmd == "reset" then 
        if not isDragging then
            RCPartyOrbs_RepositionOrbs()
        end
    elseif cmd == "debug" then 
        RCPartyOrbsDB.debugMode = not RCPartyOrbsDB.debugMode
        print("RCPartyOrbs debug mode:", RCPartyOrbsDB.debugMode and "ON" or "OFF")
        if RCPartyOrbsDB.debugMode then
            print("=== RCPartyOrbs Debug Info ===")
            print("Addon enabled:", tostring(RCPartyOrbsDB.enabled))
            print("showPlayerOrbs:", tostring(RCPartyOrbsDB.showPlayerOrbs))
            print("Test mode:", tostring(testMode))
            print("In raid:", tostring(IsInRaid()))
            print("In party:", tostring(GetNumGroupMembers() > 1))
            print("Party members:", GetNumGroupMembers() - 1)
            print("Orb count:", #orbFrames)
            for i, orb in ipairs(orbFrames) do
                print("  Orb", i, "unit:", orb.unit, "visible:", orb:IsShown())
            end
            print("=== End Debug ===")
        end
    elseif cmd == "toggle" then
        RCPartyOrbsDB.enabled = not RCPartyOrbsDB.enabled
        ReloadUI() 
    elseif cmd == "firecolor" then
        RCPartyOrbs_OpenColorPicker("fire")
    elseif cmd == "greencolor" then
        RCPartyOrbs_OpenColorPicker("green")
    elseif cmd == "yellowcolor" then
        RCPartyOrbs_OpenColorPicker("yellow")
    elseif cmd == "debuff" or cmd == "debufftest" then
        -- Cycle through debuff test colors: off -> poison -> disease -> curse -> magic -> off
        if not testDebuffMode then
            testDebuffMode = true
            testDebuffType = "Poison"
            print("RCPartyOrbs: Debuff test - POISON (Green)")
        elseif testDebuffType == "Poison" then
            testDebuffType = "Disease"
            print("RCPartyOrbs: Debuff test - DISEASE (Brown)")
        elseif testDebuffType == "Disease" then
            testDebuffType = "Curse"
            print("RCPartyOrbs: Debuff test - CURSE (Purple)")
        elseif testDebuffType == "Curse" then
            testDebuffType = "Magic"
            print("RCPartyOrbs: Debuff test - MAGIC (Blue)")
        else
            testDebuffMode = false
            testDebuffType = nil
            print("RCPartyOrbs: Debuff test OFF")
        end
        UpdateAllOrbs()
    elseif cmd == "debuff off" or cmd == "debuffoff" then
        testDebuffMode = false
        testDebuffType = nil
        print("RCPartyOrbs: Debuff test OFF")
        UpdateAllOrbs()
    elseif cmd == "dispelcheck" or cmd == "dispel" then
        -- Force refresh dispel detection and show what player can dispel
        print("|cFF00FF00=== RCPartyOrbs Spell Check ===|r")
        local _, playerClass = UnitClass("player")
        print("Player Class: |cFFFFFF00" .. playerClass .. "|r")
        
        -- Force refresh
        wipe(playerDispelList)
        debugMode = true
        UpdatePlayerDispels()
        debugMode = false
        
        -- Show dispel summary
        local types = {}
        for k, _ in pairs(playerDispelList) do table.insert(types, k) end
        if #types > 0 then
            print("|cFF00FF00Can dispel:|r " .. table.concat(types, ", "))
        else
            print("|cFFFF0000Cannot dispel anything|r - check if you have a dispel spell learned")
        end
        print("Dispel Spell: |cFFFFFF00" .. (CLASS_DISPEL_SPELLS[playerClass] or "None") .. "|r")
        
        -- Show battle rez
        local rezData = CLASS_REZ_SPELLS[playerClass]
        if rezData and rezData.combat then
            print("Battle Rez: |cFFFFFF00" .. rezData.combat .. "|r")
        else
            print("Battle Rez: |cFFFF0000None|r")
        end
        
        -- Show current modifier
        local modNames = {["shift"]="Shift", ["alt"]="Alt", ["ctrl"]="Ctrl"}
        local currentMod = RCPartyOrbsDB.clickModifier or "shift"
        print("Click Modifier: |cFFFFFF00" .. (modNames[currentMod] or "Shift") .. "+Click|r to cast")
        print("|cFF888888Left-click = Target, " .. (modNames[currentMod] or "Shift") .. "+Click = Dispel/Rez|r")
    elseif cmd == "restoreelvui" or cmd == "fixelvui" or cmd == "restoreui" or cmd == "fixui" then
        RCPartyOrbs_ForceRestoreAllUnitFrames()
    else 
        Handle_RCPartyOrbsGUI() 
    end
end -- SlashCmdList handler
