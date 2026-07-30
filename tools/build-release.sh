#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repak="${REPAK:-$root/../fast-customer-turns/tools/repak/repak_cli-x86_64-unknown-linux-gnu/repak}"
version="2.0.0"
work="$(mktemp -d /tmp/opencode/bhi-release.XXXXXX)"
trap 'rm -rf "$work"' EXIT

[[ -x "$repak" ]] || { printf 'repak not found: %s\n' "$repak" >&2; exit 1; }
command -v unzip >/dev/null || { printf 'unzip not found\n' >&2; exit 1; }
[[ -d "$root/analysis/mod" ]] || {
    printf 'cooked asset staging not found: %s\n' "$root/analysis/mod" >&2
    exit 1
}
mkdir -p "$root/dist"

lua_bin="${LUA:-}"
if [[ -z "$lua_bin" ]]; then
    lua_bin="$(command -v luajit || command -v lua || true)"
fi
[[ -n "$lua_bin" ]] || { printf 'Lua interpreter not found\n' >&2; exit 1; }
(
    cd "$root"
    "$lua_bin" -e 'assert(loadfile("BetterHandInventory/Scripts/config.lua")); assert(loadfile("BetterHandInventory/Scripts/inventory_model.lua")); assert(loadfile("BetterHandInventory/Scripts/main.lua")); assert(loadfile("BetterHandInventory/Scripts/plus.lua"))'
    "$lua_bin" tests/inventory_model_spec.lua
)

pak="$work/zzzzzzzz_BetterHandInventory_P.pak"
"$repak" pack "$root/analysis/mod" "$pak" --quiet

build_edition() {
    local edition="$1"
    local archive="$root/dist/Better-Hand-Inventory-$edition-$version.zip"
    local stage="$work/$edition"

    mkdir -p "$stage"
    cp -R "$root/BetterHandInventory" "$stage/BetterHandInventory"
    cp "$pak" "$stage/zzzzzzzz_BetterHandInventory_P.pak"
    cp "$root/README.md" "$stage/README.md"

    if [[ "$edition" == "Standard" ]]; then
        rm "$stage/BetterHandInventory/Scripts/plus.lua"
    else
        perl -0pi -e 's/Edition = "Standard"/Edition = "Plus"/' \
            "$stage/BetterHandInventory/Scripts/config.lua"
    fi

    rm -f "$archive"
    (cd "$stage" && zip -q -r "$archive" .)

    local verify="$work/verify-$edition"
    mkdir -p "$verify"
    unzip -q "$archive" -d "$verify"
    cmp "$root/BetterHandInventory/enabled.txt" "$verify/BetterHandInventory/enabled.txt"
    cmp "$root/BetterHandInventory/Scripts/main.lua" "$verify/BetterHandInventory/Scripts/main.lua"
    cmp "$root/BetterHandInventory/Scripts/inventory_model.lua" "$verify/BetterHandInventory/Scripts/inventory_model.lua"
    cmp "$root/README.md" "$verify/README.md"
    cmp "$pak" "$verify/zzzzzzzz_BetterHandInventory_P.pak"
    if [[ "$edition" == "Standard" ]]; then
        [[ ! -e "$verify/BetterHandInventory/Scripts/plus.lua" ]]
        cmp "$root/BetterHandInventory/Scripts/config.lua" "$verify/BetterHandInventory/Scripts/config.lua"
    else
        cmp "$root/BetterHandInventory/Scripts/plus.lua" "$verify/BetterHandInventory/Scripts/plus.lua"
        local plus_config="$work/plus-config.lua"
        cp "$root/BetterHandInventory/Scripts/config.lua" "$plus_config"
        perl -0pi -e 's/Edition = "Standard"/Edition = "Plus"/' "$plus_config"
        cmp "$plus_config" "$verify/BetterHandInventory/Scripts/config.lua"
    fi
    printf '%s\n' "$archive"
}

build_edition "Standard"
build_edition "Plus"
