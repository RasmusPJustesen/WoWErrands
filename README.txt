WoWErrands 2.0.1 - WoW Forever 1.60.1 (interface 16001)
=======================================================

INSTALL
1. Exit World of Warcraft.
2. Replace Interface/AddOns/WoWErrands with the WoWErrands folder
   included in this ZIP. Do not keep multiple versions of the folder.
3. Keep Spoken_Zones installed/enabled for an exact Zone Lore visual match.
4. Restart WoW.

The addon remains independent and can run without Spoken Zones. When
Spoken_Zones is present, WoWErrands uses its actual quest-log parchment,
ornament, inset rim and the same native panel and side-tab templates.
Without Spoken_Zones, it uses the bundled fallback parchment.

BEHAVIOR
- Opening Map & Quest Log shows Zone Errands beside Zone Lore (when open),
  otherwise beside the map. The panel height and its width match the map/
  Zone Lore when possible.
- Closing Zone Errands turns it into a side tab. The tab never appears while
  the panel is open. Closing Zone Lore allows both tabs to stack on the map
  edge, using the same button template.
- Zone Errands lists errands for the zone selected on the world map, including
  completed errands, which can be checked, unchecked, removed or added.
- Entering a zone with unfinished errands opens the arrival checklist and
  creates a native, collapsible Errands category INSIDE Blizzard's All
  Objectives tracker, ordered after Professions. Clicking an item completes it.
  Errands disappears in zones without unfinished tasks. The collapse state is
  remembered per character.
- /we and /wowerrands open the map (or toggle Zone Errands if already open).
- Existing character-specific SavedVariables (WoWErrandsDB) are retained.

VISUAL SOURCE
The map panel styling is based on the actual MapPanel.lua, LorePage.lua and
TextView.lua from Spoken Zones (rusty-key, MIT-licensed UI code):
https://github.com/rusty-key/spoken-wow
This package does not redistribute Spoken's original art files. Instead it
references artwork from the user's existing Spoken_Zones installation.

TESTING
The files are packaged for WoW Forever 1.60.1. The objective tracker module
integration requires in-game testing. It uses Blizzard's built-in
ObjectiveTrackerModuleTemplate and ObjectiveTrackerManager; it does not replace
or manually reposition the Blizzard tracker.
