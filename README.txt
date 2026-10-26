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
- Opening Map & Quest Log shows the Zone Errands panel. It is placed beside
  Zone Lore where possible and can be collapsed into a map-edge clipboard tab.
- The map panel uses the same Forever panel template and original parchment
  art from Spoken Zones when that addon is available.

MAP PINS AND WAYPOINTS
- Select a zone on the world map and add an errand.
- Click Pin beside that errand, then click its location on the zone map.
- Click the map pin itself or use Go beside the errand to set a Blizzard waypoint.
- Right-click Go to replace an existing pin. Use Cancel while placing a pin.
- The game only allows waypoints on maps supported by C_Map.

MANUAL COMPLETION
- Errands are completed by clicking their checkbox. No automatic completion
  rules are evaluated in this version. Previously configured rules are inactive.

REORDER AND OVERVIEW
- Use ^ and v beside the x (Remove) button to move an errand up or down. That order also
  applies to the native All Objectives section.
- SHIFT-click an errand's name or checkbox in the Zone Errands map panel
  to track it persistently in All Objectives, even when you leave the zone.
  SHIFT-click again to untrack it. The same shortcut works in All zones.
- New/previous errands appear automatically while in their zone, unless
  explicitly untracked; tracking preferences are saved per character.
- Click All zones in the Zone Errands panel to see a grouped list of all
  unfinished errands across Azeroth. Click a zone or errand to open its map.
- Existing errands from older versions have no map ID until a zone is opened
  in the map or can be resolved through C_Map's zone catalog.

COMMANDS
/we or /wowerrands  Open the map-based Zone Errands panel.

DESIGN AND DEPENDENCIES
Special thanks to rustykey, author of Spoken (Spoken Player), whose Zone Lore
interface inspired the copper and parchment design. Spoken_Zones is optional.
Where installed, its artwork is used at runtime to match Zone Lore; its
original art is not redistributed in this ZIP. Without Spoken, WoWErrands
uses a bundled parchment fallback and Blizzard frames.

COMPATIBILITY
Target: WoW Forever 1.60.1 (Interface 16001, Camelot). Client APIs may
change between Forever builds. This release was syntax-checked and tested
with a simulated addon UI; it has NOT been verified inside a running client.
Please report errors at https://github.com/RasmusPJustesen/WoWErrands/issues
