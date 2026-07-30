# Better Hand Inventory

Quality-of-life inventory mod for Retro Rewind - Video Store Simulator.

[Nexus Mods](https://www.nexusmods.com/retrorewindvideostoresimulator/mods/273) |
[Releases](https://github.com/fenomelini/better-hand-inventory/releases) |
[Issues](https://github.com/fenomelini/better-hand-inventory/issues)

## Editions

Install exactly one edition:

- **Standard** adds native bidirectional hand scrolling and automatic VHS
  ordering.
- **Plus** includes Standard and adds delivery-box retrieval, matching-tape
  markers, and collection to the return counter.

Standard and Plus use the same mod and PAK names and must not be installed
together.

## Standard Features

- Scroll through the held stack in both directions with the mouse wheel.
- Sort movie tapes by numeric genre and SKU.
- Keep the current tape in hand while sorting the circular sequence behind it.
- Leave miscellaneous products and mixed/non-movie stacks in vanilla order.
- Preserve vanilla pickup, attachment, UI, ownership, inventory, and save calls.

The scroll fix runs inside the original cooked Blueprint. The Lua module does
not hook scrolling or inventory pickup functions; it observes membership at a
low frequency and only writes a verified ordering when the stack changes.

## Plus Features

- `F5`: move the nearest free delivery box in front of the player.
- `F6`: mark or unmark every stored copy matching the held movie SKU.
- `F7`: safely release marked tapes from normal shelves and arrange them on the
  return counter in a five-by-two layered grid.
- Publish optional counters to StatHead when StatHead is installed.
- Refuse to activate if Inventory QoL is detected.

Plus excludes reserved-shelf tapes and requires reciprocal tape/container
ownership before collecting anything. Scanner, rewinder, checkout, customer,
hand, and inventory workflows are not treated as normal shelf storage.

## Requirements

- UE4SS `3.0.1 Beta #0`.
- Retro Rewind Steam build `23896268` (App ID `3552140`).
- Unreal Engine `5.4.4`.

Reflected names and the cooked `Player_Character` override are build-specific.

## Installation

1. Install UE4SS in `RetroRewind/Binaries/Win64`.
2. Copy `BetterHandInventory` to
   `RetroRewind/Binaries/Win64/ue4ss/Mods`.
3. Copy `zzzzzzzz_BetterHandInventory_P.pak` to
   `RetroRewind/Content/Paks/~mods`.
4. Restart the game.

Expected files include:

```text
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/enabled.txt
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/Scripts/config.lua
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/Scripts/inventory_model.lua
RetroRewind/Binaries/Win64/ue4ss/Mods/BetterHandInventory/Scripts/main.lua
RetroRewind/Content/Paks/~mods/zzzzzzzz_BetterHandInventory_P.pak
```

## Configuration

Edit `BetterHandInventory/Scripts/config.lua` before loading or hot-reloading
the mod:

- `Edition` is set by the downloaded Standard or Plus archive; switch editions
  by installing the other archive rather than editing this value.
- `SortMoviesByGenre`: enable automatic movie ordering.
- `GrabDeliveryBoxes`, `MarkMatchingTapes`, `CollectMarkedTapes`: enable Plus
  actions.
- `GrabBoxKey`, `MarkTapeKey`, `CollectTapeKey`: configure Plus keys.
- `DeliveryBoxMaxDistance`: maximum delivery-area search radius.
- `CollectionCapacity`: maximum number of tapes arranged on the counter.
- `InitialStateDelayMs`, `BaselinePollIntervalMs`: inventory observation timing.
- `DebugLogging`: enable successful-operation diagnostics.

Lua/config changes can be reloaded in game with `Ctrl+R`. PAK changes require a
full restart.

## Console Commands

```text
betterhandinventory status
betterhandinventory dump
betterhandinventory sort
```

## Compatibility

- Do not use Inventory QoL at the same time as Better Hand Inventory Plus.
- Mods that override
  `RetroRewind/Content/VideoStore/core/pawn/Player_Character` conflict with the
  bidirectional scroll fix.
- Faster Returns uses separate scanner/rewinder workflows; Plus only collects
  tapes with valid normal-shelf ownership.
- Plus releases marked tape references before day-transition world unloading.
- Genre additions remain sortable because ordering compares numeric values.

## Uninstallation

Delete both `BetterHandInventory` and
`zzzzzzzz_BetterHandInventory_P.pak`, then restart the game. The mod does not
require a new save.

## Version

`2.0.0`
