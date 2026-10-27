# RCPartyOrbs Changelog

## Version 2.3.1
- **Wrath Titan Reforged supported** (client 3.80), checked in the Chinese game language.
- Release jobs updated to GitHub's newer Node 24 actions (no more Node.js 20 warning).

## Version 2.3.0
Works on every WoW client: Retail (Midnight), MoP Classic, Cata, Wrath, TBC Anniversary, Classic Era and WoW Forever.

### Retail and WoW Forever
- **Party orbs keep working in combat.** These clients hide party members' exact health and power from addons during combat; the orbs now fill from the game's readable percentage instead, and the numbers still show.
- **Fixed errors from removed aura functions** (UnitBuff / UnitDebuff are gone on Retail). Dispel colors and the purge highlight on the target orb work again, out of combat; in combat the game hides debuff types, so the orbs simply don't recolor then.
- Threat borders, range, offline and dead checks no longer error on values the game hides.

### All clients
- **Right-click menu works again on the Classic clients.** Classic Era, TBC, Cata and MoP Classic moved to Blizzard's newer menu system and removed the old party/player dropdowns, so right-clicking an orb did nothing there. It now uses the newer menu wherever it exists.
- **Color pickers fixed on the Classic clients** for the same reason (they use the newer color picker now).
- **WoW Forever runs the Retail interface**, so it now takes the Retail code paths instead of the Classic Era ones.
- **TBC Anniversary and WoW Forever are supported** (new TOC files), and the version numbers for Retail 12.1 and Classic Era 1.15.9 are current.
- Fixed the options window sliders using an old function some clients no longer have.
- RC Party Orbs now lives on GitHub; releases are built and uploaded to CurseForge automatically.
- Checked end to end on every client: every options control and slash command, debuffed, dead, offline and out-of-range party members, raids, vehicles, every event the addon listens for, and nothing touches protected frames in combat.

## Version 2.2.9
### Bug Fixes
- **Target orb now flips above the party orb on the first pass** - The
  "flip the target above when the orbs are near the bottom of the screen"
  decision read the player orb's live GetCenter(), which is stale at load and
  immediately after any reposition (the frame hasn't settled into its applied
  position yet). It reported mid-screen, so the flip never triggered and the
  target went below - until you toggled orientation, which re-ran the layout
  after the orb had settled. That's why swapping horizontal/vertical and back
  "fixed" it.
- The flip is now computed from the player orb's intended (saved) anchor
  instead of live geometry, so a bottom-anchored layout puts the target above
  immediately on login with no toggle needed. Falls back to live centre, then
  screen centre, if no saved position exists.

## Version 2.2.8
### Bug Fixes
- **Target orb no longer sits buried under the party orb** - Two causes.
  (1) Target orb containers are created at a lower frame level than party
  orbs (2 vs 10, an intentional click-priority choice), and since the orb
  bodies share the LOW strata, any overlap meant the party orb drew
  completely over the target. (2) The unit name sits ~35% of the orb height
  ABOVE each orb; in horizontal layout the target orb goes above/below the
  party orb, so that name text landed in the gap and collided.
- PositionOrbs now adds the name overhang into the target orb's vertical gap
  so names clear the neighbouring orb, and clamps negative target spacing to
  zero so orb bodies can never physically overlap (a negative saved spacing
  was enough to bury the target completely).
- Click targeting is unaffected: it relies on the hit-rect dead zone between
  orbs, not on frame level.

## Version 2.2.7
### Bug Fixes
- **Fixed 5 XML parser warnings from the minimap button** - The icon TexCoord
  element was singular; the UI schema element is `TexCoords` (plural). The
  parser rejected the whole element and then each of its four attributes,
  producing:
  `Unrecognized XML: TexCoord` plus `Unrecognized XML attribute: left/right/top/bottom`
  The icon was silently rendering untrimmed (full 0-1 coords) instead of the
  intended 0.07-0.93 crop.

## Version 2.2.6
### Bug Fixes
- **Fixed ADDON_ACTION_BLOCKED on orb resize in combat** - The orb containers
  inherit SecureUnitButtonTemplate (so they stay click-to-target), which makes
  them protected frames. SetSize/SetPoint/ClearAllPoints on them are blocked
  during combat lockdown, producing:
  `AddOn 'RCPartyOrbs' tried to call the protected function 'RCPartyOrbFrame1:SetSize()'`
  Most commonly triggered by RCPartyOrbs_FullInit setting the size slider on
  PLAYER_ENTERING_WORLD while already in combat.
- All container geometry now routes through a SecureHandlerAttributeTemplate
  proxy (RCPartyOrbsSizer). Layout maths stays in normal Lua; the restricted
  snippet applies the result, which is permitted mid-combat. Live slider
  resizing keeps working during combat with no taint.
- Affects RCPartyOrbs_ApplyOrbSize, RCPartyOrbs_ApplyTargetOrbSize,
  PositionOrbs, and the position-undo path.

## Version 74 (Latest)
### New Features
- **Reorganized Advanced Menu** - Cleaner menu structure with sub-menus
  - **Orb Colors Sub-Menu** - All power type color pickers in one place
    - Health, Mana, Rage, Energy, Focus, Runic Power, Chi (Monk)
    - Reset Defaults button to restore original colors
    - Features Sindragosa background with icy blue border
  - **Threat Colors Sub-Menu** - Customize threat border colors
    - High (Red), Medium (Yellow), Low (Green) threat borders
    - Features Deathwing background with fiery orange border
  - Sub-menus are mutually exclusive (only one open at a time)
  - All sub-menus close automatically when closing Advanced menu

- **Per-Character Color Settings** - Orb colors are now saved per character
  - Each character has their own health and power type color settings
  - Health orb defaults to your class color
  - Power type colors use standard WoW power colors by default
  - Reset Defaults restores class-specific colors for current character

### Fixes
- **Color Picker Instant Update** - Changing orb colors now applies immediately
  - Previously required casting a spell to see color changes
  - Now forces a full orb refresh after color selection
  
- **Mana Orb Dark Ring Fix** - Fixed dark/black ring appearing on mana orbs
  - Gloss overlay now tints based on power type color
  - Provides consistent brightness across all power types

- **Color Picker Save Fix** - Fixed color picker not saving the correct color type
  - Color type now properly persists through picker callbacks
  - Works correctly for all power types (mana, rage, energy, etc.)

### UI Improvements
- Sub-menus properly spaced (100px gap) to prevent flame border overlap
- Sub-menus anchor to top-right of Advanced menu for consistent positioning
- Removed old color buttons from main Advanced menu (now in sub-menus)

---

## Version 73
### New Features
- **Multi-Version Compatibility** - Now works on ALL WoW versions:
  - Retail (The War Within / Dragonflight)
  - MoP Remix
  - Cataclysm Classic
  - Wrath Classic
  - Classic Era / Hardcore
  - Automatic detection - just install and play!

- **Custom Debuff Alert Sounds** - Choose from 24 different sounds for debuff notifications
  - New dropdown menu in settings to select your preferred sound
  - Includes: Affliction Alert (new default), Mario sounds, Zelda sounds, Warcraft peon quotes, and more
  - Preview plays when selecting a new sound
  - Your selection is saved between sessions

- **Improved Death Detection** - Dead party members now show immediately
  - Grey/empty orbs with red "DEAD" text
  - Instant visual feedback via UNIT_FLAGS event
  - Battle rez (Shift+click) is now more responsive

- **Multi-Addon Compatibility** - Now supports hiding/showing frames from multiple unit frame addons:
  - ElvUI
  - Shadowed Unit Frames (SUF)
  - Pitbull4
  - Z-Perl / X-Perl
  - Luna Unit Frames
  - Works automatically - RCPartyOrbs detects which addon you're using

### Fixes
- **Raid Auto-Hide** - ALL orbs now properly hide when converting party to raid
  - Previously only party orbs were hidden, now player orb hides too
  - Orbs automatically return when leaving raid

- **ElvUI Combat Compatibility** - Fixed "action blocked" errors with ElvUI raid frames
  - Now uses SetAlpha instead of Hide/Show to avoid triggering ElvUI's SecureStateDriver
  - No longer causes cascade updates to raid frames during combat
  - Frames become invisible and non-clickable without actually hiding
  - Also hides ElvUI portraits correctly

- **Combat Lockdown Protection** - All unit frame operations check for combat lockdown
  - Prevents protected function errors during combat

### New Commands
- `/fpo restoreui` or `/fpo fixui` - Emergency restore all unit frame addon frames

---

## Version 72
### New Features
- **Separate Target Spacing Slider** - Added independent spacing control for target orbs
  - "Party Spacing" slider controls distance between party member orbs
  - "Target Spacing" slider controls distance between each orb and its target orb
  - Both sliders displayed side-by-side in the settings menu

### Fixes
- Fixed orientation toggle (horizontal/vertical) not working when positions were saved
- Party target orbs now always stay anchored to their corresponding party members
- Role icon repositioned to bottom of mana orb and made smaller

---

## Version 70-71
### New Features
- **Cast Bar Scaled Up** - Arc now matches the outside edge of the mana orb (20 segments)
- **Debuff Sound Notification** - Plays a bell/gong sound when a dispellable debuff is detected
- **Level Display** - Character level now shows after the player name (e.g., "Papawoody 80")
- **Role Icons** - Tank/Healer/DPS icons displayed for party members
  - Shield icon for tanks
  - Cross icon for healers
  - Sword icon for DPS

### New Settings (Orb Visibility Menu)
- Show Level toggle
- Show Role Icon toggle

### Fixes
- Shift-click now passes through for normal spell casting (fixes Soulstone on party members)

---

## Version 68-69
### New Features
- **Arc-Style Cast Bars** - Curved cast bar displayed below each mana orb
  - 16-20 texture segments arranged in a decorative arc
  - Gold color for interruptible spells
  - Grey color for non-interruptible spells
  - Spell name and cast time displayed below arc
  - Supports both normal casts (fills left-to-right) and channeled spells (drains right-to-left)
  - Completely transparent background for clean visual integration

### New Settings
- Show Cast Bars toggle in Orb Visibility menu

---

## Version 66-67
### New Features
- **Offline Detection** - Party members who go offline show:
  - Black/dark grey orbs
  - "Offline" text instead of health percentage
  - Grey name text

- **Out of Range Detection** - Party members out of range show:
  - Greyed/desaturated orb colors
  - Slightly transparent appearance

### Visual Changes
- All fonts changed to white for consistency
- Health percentage font size reduced to 18 (matches health value)

---

## Version 62-65
### New Features
- **Orb Visibility Menu** - New dedicated menu for visibility controls
  - Individual toggles for Player, Party 1-4, and Target orbs
  - Individual toggles for Party 1-4 Target orbs
  - Organized sections: Player & Target, Party Members, Party Targets, Other Options

- **ElvUI Frame Hiding** - Option to hide ElvUI's default unit frames
  - Hides player, target, and party frames when enabled
  - Includes pet frames
  - Toggle in Orb Visibility menu

---

## Version 60-61
### New Features
- **Party Target Orbs** - Shows what each party member is targeting
  - Smaller orbs displayed next to each party member
  - Automatically positioned based on layout orientation
  - Individual visibility toggles for each party target

### Layout Behavior
- Horizontal layout: targets appear below their party member
- Vertical layout: targets appear to the right of their party member

---

## Version 58-59
### UI Improvements
- Reorganized configuration menu layout
- Moved modifier dropdown to Advanced menu
- Repositioned font size slider
- Removed redundant checkboxes
- Fixed button overlap issues

---

## Version 55-57
### New Features
- **Configurable Click Modifier** - Choose between Shift, Alt, or Ctrl for dispel/rez clicks
  - Dropdown selector in Advanced menu
  - Changes apply immediately without /reload

- **Font Size Slider** - Adjustable font scaling (50%-150%)
  - Affects health %, health value, mana value, and name text

---

## Version 52-54
### New Features
- **Battle Resurrection Support** - Modifier+click on dead party members casts:
  - Rebirth (Druid)
  - Raise Ally (Death Knight)
  - Soulstone (Warlock)

### Fixes
- Fixed click-to-dispel targeting (now properly targets the clicked unit)
- Improved combat-safe macro system

---

## Version 49-51
### New Features
- **Click-to-Dispel** - Shift+click on party members to dispel debuffs
  - Automatically detects player's dispel abilities
  - Works in combat using secure macro system

- **Debuff/Dispel Color System** - Orbs change color based on debuff type
  - Purple for Curse
  - Green for Poison  
  - Brown for Disease
  - Blue for Magic
  - Colors apply to both health orb and mana orb

- **Purgeable Buff Detection** - Enemy target orb highlights when target has purgeable buffs

---

## Version 45-48
### New Features
- **Threat Detection** - Fire border appears around orbs when party member has aggro
  - Uses WoW's UnitThreatSituation API
  - Animated fire effect for high threat

### Fixes
- Fixed threat detection using proper API (switched from nameplate iteration to automatic aggregation)

---

## Core Features (All Versions)
- Diablo 3-style health and mana orbs
- Animated galaxy/swirl effects inside orbs
- Class-colored health orbs
- Power type-colored mana orbs (mana, rage, energy, etc.)
- Customizable orb size and spacing
- Horizontal or vertical party layout
- Draggable positioning (drag player orb to move group)
- Minimap button for quick access
- Test mode for configuration
- Frame lock/unlock system
