# WoWErrands

A lightweight, zone-based to-do addon for **World of Warcraft: Forever**.

Remember why you traveled to a zone: visit a profession trainer, pick up a quest, buy supplies, or complete anything else you don't want to forget.

## Features

- **Zone-entry checklist:** Opens when you enter a zone with unfinished errands.
- **Native objective tracker section:** Displays a collapsible **Errands** group inside **All Objectives**, alongside Quests and Professions.
- **Map-side editor:** Manage errands for the zone selected on the world map.
- **Zone Lore-inspired styling:** WoW-style parchment, borders and side-tab controls. When **Spoken Zones** is installed, the map panel can reference the same parchment artwork for a closer visual match.
- **Per-character lists:** Saved between sessions using WoW's SavedVariables.
- **In-game editing:** Add, complete and remove errands without editing files.

## Installation

1. Download the latest `WoWErrands-x.y.z.zip` from [Releases](../../releases).
2. Close WoW and unzip it into the game's `Interface/AddOns/` directory.
3. Verify the folder is `Interface/AddOns/WoWErrands/` and contains `WoWErrands.toc`.
4. Launch WoW and enable **WoWErrands** in the addon list.

### Optional dependency

[Spoken Zones](https://github.com/rusty-key/spoken-wow) is optional, but recommended if you want the map panel to match its **Zone Lore** design. WoWErrands runs without it using fallback artwork.

## Using WoWErrands

Open your world map to edit the errands belonging to the selected zone. The **Zone Errands** side panel can be collapsed into a tab attached to the map edge.

Entering a zone with incomplete errands brings up the checklist. The same pending errands can be viewed in **All Objectives > Errands**.

Chat shortcuts are available if needed:

- `/we` or `/wowerrands`: Open the map and Zone Errands interface.

## Compatibility

The initial release is **2.0.0**, targeting **WoW Forever 1.60.1** (`## Interface: 16001`). Later client updates may require changes to API calls or the manifest interface version.

## Development and releases

- The addon files may be kept at the repository root or inside a `WoWErrands/` folder.
- `scripts/validate-addon.sh` checks TOC files and Lua syntax (when `luac5.1` is installed).
- Pushes and pull requests to `main` run the validation workflow.
- Publishing a tag such as `v2.0.0` runs the release workflow and generates `WoWErrands-2.0.0.zip` automatically.
- **Before tagging**, update `## Version` in both `WoWErrands.toc` and `WoWErrands_Camelot.toc` to match the tag. The release workflow enforces this.

GitHub automation packages and publishes code already committed to this repository; it does **not** automatically fix compatibility problems after a WoW Forever update.

## Artwork and attribution

UI implementation is inspired by Spoken Zones' map panel and quest-log page. WoWErrands does not bundle Spoken's original artwork; it may reference files from a locally installed copy of Spoken Zones.

World of Warcraft and associated game artwork belong to their respective rights holders. This is an unofficial community addon.

No redistribution license is included in this repository setup. Choose a license deliberately before inviting outside contributions or reuse.
