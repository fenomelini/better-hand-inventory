# Better Hand Inventory

Quality-of-life mod for Retro Rewind - Video Store Simulator that fixes held
inventory scrolling and keeps VHS tapes organized.

[Nexus Mods](https://www.nexusmods.com/retrorewindvideostoresimulator/mods/273) |
[Releases](https://github.com/fenomelini/better-hand-inventory/releases) |
[Issues](https://github.com/fenomelini/better-hand-inventory/issues)

## Features

- Scroll the held stack in both directions with the mouse wheel.
- Sort VHS tapes by numeric genre and then SKU.
- Keep the newly collected tape visible while organizing the circular sequence
  behind it.
- Leave miscellaneous products and other non-movie stacks in vanilla order.
- Preserve vanilla pickup, attachment, UI, inventory, ownership, and save
  behavior.

## Requirements

- [UE4SS](https://github.com/UE4SS-RE/RE-UE4SS/releases) is required.
- Tested with UE4SS `3.0.1 Beta #0`.
- Steam App ID `3552140`, build ID `23896268`.
- Unreal Engine `5.4.4`.

## Installation

1. Install UE4SS in `RetroRewind/Binaries/Win64`.
2. Place `BetterHandInventory` in
   `RetroRewind/Binaries/Win64/ue4ss/Mods`.
3. Restart the game completely.

The resulting paths should include:

```text
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/enabled.txt
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/Scripts/config.lua
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/Scripts/main.lua
```

## How It Works

The game already passes a signed wheel direction to its inventory function, but
the vanilla Blueprint selects the first stacked object for either sign. The mod
lets positive scrolling use that vanilla path. After a negative scroll, it uses
the player's original hand-to-stack, stack-to-hand, and reorganize functions to
move to the previous object safely.

After collection, movie references already present in `Objects Inventory` are
ordered by genre and SKU. The held object stays in hand, so collecting a tape
does not immediately replace it with another one. The mod does not spawn,
destroy, duplicate, or remove inventory objects.

## Configuration

Edit `BetterHandInventory/Scripts/config.lua` before starting the game:

- `BidirectionalScroll`: enable the negative-direction correction.
- `SortMoviesByGenre`: organize movie stacks by genre and SKU.
- `InitialStateDelayMs`: wait before capturing a loaded inventory baseline.
- `BaselinePollIntervalMs`: refresh the baseline after loading or map changes.
- `InventorySettleMs`: debounce interval after inventory changes.
- `AutoDumpAfterInventoryChange`: write complete stack diagnostics to the log.
- `DebugLogging`: log successful and skipped internal operations.

## Console Commands

```text
betterhandinventory status
betterhandinventory dump
betterhandinventory sort
```

`sort` manually organizes the current movie stack. `dump` writes the current
held object and stack metadata to `UE4SS.log`.

## Compatibility

- Mods that hook or replace `Player_Character_C` inventory scrolling may
  conflict.
- Reverse Inventory changes the same general stack workflow and should not be
  used without explicit compatibility testing.
- Genre additions remain sortable because the mod compares numeric enum values
  instead of hardcoding genre names.

## Uninstallation

Delete the `BetterHandInventory` folder from `ue4ss/Mods`, then restart the
game. The mod does not alter save files or require a new save.

## Version

`1.0.0`
