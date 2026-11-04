WoWErrands 3.0.3 - WoW Forever 1.60.1 (Interface 16001)
======================================================

INSTALL
1. Exit World of Warcraft.
2. Replace Interface/AddOns/WoWErrands with the enclosed WoWErrands folder.
3. Restart World of Warcraft. Avoid keeping duplicate addon folders.

WoWErrands uses character-specific SavedVariables: WoWErrandsDB. Version 3.0.3
migrates existing errands in place and preserves their completed state and order.

WHAT IT DOES
- On entering a zone with unfinished errands, the native All Objectives tracker
  expands the Errands category and briefly flashes its entries in gold.
- No separate zone-entry popup is displayed.
- In All Objectives, unfinished errands for the current zone appear automatically,
  and manually tracked errands from other zones stay visible. Left-click an
  errand to complete it manually; Shift-click to set a waypoint if it has a pin.
- Map & Quest Log shows a collapsible Errands category in the quest log,
  below your quests, for the zone selected on the map. Click the Errands
  header to collapse or expand it.
- Everything works with plain clicks, so the gamepad cursor can use it too.

MAP PINS AND WAYPOINTS
- Select a zone on the world map and add an errand.
- Click the errand's name to show its actions, click Pin, then click its
  location on the zone map. Use Cancel while placing a pin.
- Click the map pin itself or use Go in the errand's actions to set a waypoint.
- Use Move in the errand's actions to replace an existing pin.
- The game only allows waypoints on maps supported by C_Map.

MANUAL COMPLETION
- Errands are completed by clicking their checkbox. No automatic completion
  rules are evaluated in this version. Previously configured rules are inactive.

REORDER AND OVERVIEW
- Use ^ and v beside the x (Remove) button in an errand's actions to move it
  up or down. That order also applies to the native All Objectives section.
- Click Track in an errand's actions (or SHIFT-click its name) to track it
  persistently in All Objectives, even when you leave the zone. Click
  Untrack to stop tracking it.
- New/previous errands appear automatically while in their zone, unless
  explicitly untracked; tracking preferences are saved per character.
- When the map shows a continent or the world, the Errands category lists
  unfinished errands across Azeroth grouped by zone. Click a zone to open it.
- Existing errands from older versions have no map ID until a zone is opened
  in the map or can be resolved through C_Map's zone catalog.

COMMANDS
/we or /wowerrands  Open the quest log with Errands expanded.

DESIGN AND DEPENDENCIES
Special thanks to rustykey, author of Spoken (Spoken Player), whose Zone Lore
interface inspired the earlier design. Spoken_Zones is optional; the Errands
category now uses the native quest log frames.

COMPATIBILITY
Target: WoW Forever 1.60.1 (Interface 16001, Camelot). Client APIs may
change between Forever builds. This release was syntax-checked and tested
with a simulated addon UI; it has NOT been verified inside a running client.
Please report errors at https://github.com/RasmusPJustesen/WoWErrands/issues
