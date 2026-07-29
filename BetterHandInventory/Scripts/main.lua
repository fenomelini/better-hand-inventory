local Config = require("config")

local MOD_NAME = "BetterHandInventory"
local PLAYER_PATH = "/Game/VideoStore/core/pawn/Player_Character.Player_Character_C:"

local hooks = {
    {
        path = PLAYER_PATH .. "Add object to Hand",
        label = "Add object to Hand",
    },
    {
        path = PLAYER_PATH .. "Remove object to Hand",
        label = "Remove object to Hand",
    },
    {
        path = PLAYER_PATH .. "Scroll Intenvory to set next Object Hold",
        label = "Scroll Intenvory to set next Object Hold",
    },
}

local registered_hooks = {}
local hook_retry_attempts = 0
local state_generation = 0
local last_membership_signature = nil
local last_stack_sequence = nil
local last_sequence_membership_signature = nil
local baseline_initialized = false
local adjusting_scroll = false
local stats = {
    reverse_scrolls = 0,
    sorts = 0,
    sort_skips = 0,
}

local PRODUCT_STRUCTURE = "Product Structure"
local BASE_STRUCTURE = "BaseStructure_2_FBB12C464AE570CAFD12ED8506160683"
local BOX_DATA = "BoxData_25_B5A798DA4F509BDCCF4B189171C1DA10"
local PRODUCT_TYPE = "TypeofProduct_28_4CF994D64BC7B26013B4E983386ABC2C"
local GENRE = "Genre_27_8F38DC364314469FC08A2AB858AC3CF8"
local SKU = "SKU_26_C5F25F4E49D05A4DEC2DEEAE5AEE5876"
local MOVIE_PRODUCT_TYPE = 1

local function log(message)
    print(string.format("[%s] %s\n", MOD_NAME, tostring(message)))
end

local function unwrap(value)
    if value == nil then return nil end

    local ok, has_get = pcall(function()
        return type(value.get) == "function"
    end)
    if not ok or not has_get then return value end

    local get_ok, result = pcall(function()
        return value:get()
    end)
    if get_ok then return result end
    return nil
end

local function valid_object(object)
    object = unwrap(object)
    if object == nil then return false end

    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function read_member(value, member_name)
    value = unwrap(value)
    if value == nil then return nil end

    local ok, member = pcall(function()
        return unwrap(value[member_name])
    end)
    if ok then return member end
    return nil
end

local function number_value(value)
    value = unwrap(value)
    if type(value) == "number" then return value end
    if value == nil then return nil end
    return tonumber(tostring(value):match("-?[%d%.]+"))
end

local function object_key(object)
    object = unwrap(object)
    if not valid_object(object) then return nil end

    local ok, address = pcall(function()
        return object:GetAddress()
    end)
    if ok then return tostring(address) end
    return tostring(object)
end

local function describe_object(object)
    object = unwrap(object)
    if not valid_object(object) then return "nil" end

    local ok, full_name = pcall(function()
        return object:GetFullName()
    end)
    if ok and type(full_name) == "string" then return full_name end
    return tostring(object)
end

local function scalar(value)
    value = unwrap(value)
    if value == nil then return "nil" end

    local ok, text = pcall(function()
        return value:ToString()
    end)
    if ok and type(text) == "string" then return text end
    return tostring(value)
end

local function item_metadata(object)
    object = unwrap(object)
    if not valid_object(object) then
        return { product_type = nil, genre = nil, sku = nil }
    end

    local product = read_member(object, PRODUCT_STRUCTURE)
    local base = read_member(product, BASE_STRUCTURE)
    local box = read_member(base, BOX_DATA)

    return {
        product_type = number_value(read_member(base, PRODUCT_TYPE)),
        genre = number_value(read_member(box, GENRE)),
        sku = number_value(read_member(box, SKU)),
    }
end

local function invoke(object, function_name, ...)
    object = unwrap(object)
    if not valid_object(object) then return false, "invalid object" end

    local argument_count = select("#", ...)
    local arguments = { ... }
    local ok, result = pcall(function()
        local reflected_function = object[function_name]
        return reflected_function(object, table.unpack(arguments, 1, argument_count))
    end)
    if not ok then return false, result end
    return true, unwrap(result)
end

local function find_player()
    local ok, player = pcall(function()
        return FindFirstOf("Player_Character_C")
    end)
    player = unwrap(player)
    if ok and valid_object(player) then return player end
    return nil
end

local function array_size(array)
    if array == nil then return nil end

    local ok, size = pcall(function()
        return array:GetArrayNum()
    end)
    if ok then return tonumber(size) end

    ok, size = pcall(function()
        return #array
    end)
    if ok then return tonumber(size) end
    return nil
end

local function collect_inventory(player)
    player = unwrap(player)
    if not valid_object(player) then return nil, nil, nil, "invalid player" end

    local held = read_member(player, "Object Hold")
    local inventory = read_member(player, "Objects Inventory")
    local count = array_size(inventory)
    if inventory == nil or count == nil then
        return held, nil, nil, "Objects Inventory unavailable"
    end

    local objects = {}
    local ok, iteration_error = pcall(function()
        inventory:ForEach(function(index, element)
            objects[index] = unwrap(element)
        end)
    end)
    if not ok then return held, inventory, nil, tostring(iteration_error) end
    if #objects ~= count then
        return held, inventory, nil, string.format("array count mismatch: %d/%d", #objects, count)
    end

    return held, inventory, objects, nil
end

local function log_item(position, object)
    local metadata = item_metadata(object)
    log(string.format(
        "%s object=%s type=%s genre=%s sku=%s",
        position,
        describe_object(object),
        scalar(metadata.product_type),
        scalar(metadata.genre),
        scalar(metadata.sku)
    ))
end

local function dump_inventory(player, reason)
    player = unwrap(player)
    if not valid_object(player) then player = find_player() end
    if not player then
        log("inventory dump skipped: player not found")
        return false
    end

    local held, _, objects, collect_error = collect_inventory(player)
    if not objects then
        log("inventory dump failed: " .. tostring(collect_error))
        return false
    end

    log(string.format("inventory dump reason=%s stack=%d", tostring(reason), #objects))
    log_item("held", held)
    for index, object in ipairs(objects) do
        log_item(string.format("stack[%d]", index), object)
    end
    return true
end

local function execute_after_delay(delay_ms, callback)
    ExecuteWithDelay(delay_ms, function()
        local queued, queue_error = pcall(function()
            ExecuteInGameThread(callback)
        end)
        if not queued then
            log("failed to queue game-thread callback: " .. tostring(queue_error))
        end
    end)
end

local function same_order(first, second)
    if #first ~= #second then return false end
    for index = 1, #first do
        if object_key(first[index]) ~= object_key(second[index]) then return false end
    end
    return true
end

local function stack_sequence(player)
    local held, _, objects = collect_inventory(player)
    if not valid_object(held) or not objects then return nil end

    local sequence = { held }
    for _, object in ipairs(objects) do
        if not valid_object(object) then return nil end
        sequence[#sequence + 1] = object
    end
    return sequence
end

local function is_forward_rotation(before, after)
    if not before or not after or #before ~= #after then return false end
    for index = 1, #before do
        local expected_index = (index % #before) + 1
        if object_key(after[index]) ~= object_key(before[expected_index]) then return false end
    end
    return true
end

local function collect_array(array)
    local count = array_size(array)
    if count == nil then return nil, "array unavailable" end

    local objects = {}
    local ok, iteration_error = pcall(function()
        array:ForEach(function(index, element)
            objects[index] = unwrap(element)
        end)
    end)
    if not ok then return nil, tostring(iteration_error) end
    if #objects ~= count then
        return nil, string.format("array count mismatch: %d/%d", #objects, count)
    end
    return objects, nil
end

local function write_array_slots(inventory, ordered)
    return pcall(function()
        inventory:ForEach(function(index, element)
            element:set(ordered[index])
        end)
    end)
end

local function write_array_order(inventory, ordered)
    if array_size(inventory) ~= #ordered then return false, "array size changed" end
    for _, object in ipairs(ordered) do
        if not valid_object(object) then return false, "ordered array contains an invalid object" end
    end

    local original, collect_error = collect_array(inventory)
    if not original then return false, collect_error end

    local preflight_ok, preflight_error = write_array_slots(inventory, original)
    if not preflight_ok then return false, "array setter preflight failed: " .. tostring(preflight_error) end

    local write_ok, write_error = write_array_slots(inventory, ordered)
    local written = collect_array(inventory)
    if write_ok and written and same_order(written, ordered) then return true, nil end

    local rollback_ok, rollback_error = write_array_slots(inventory, original)
    local restored = collect_array(inventory)
    if not rollback_ok or not restored or not same_order(restored, original) then
        return false, string.format(
            "array write failed (%s); rollback failed (%s)",
            tostring(write_error),
            tostring(rollback_error)
        )
    end

    return false, "array write failed and was rolled back: " .. tostring(write_error)
end

local function inventory_signature(held, objects)
    local keys = {}

    if valid_object(held) then keys[#keys + 1] = object_key(held) end
    for _, object in ipairs(objects) do
        local key = object_key(object)
        if not key then return nil end
        keys[#keys + 1] = key
    end

    table.sort(keys)
    return table.concat(keys, ":")
end

local function membership_signature(player)
    local held, _, objects = collect_inventory(player)
    if not objects then return nil end
    return inventory_signature(held, objects)
end

local function sort_movie_inventory(player)
    local held, inventory, objects, collect_error = collect_inventory(player)
    if not valid_object(held) or not objects then return false, collect_error or "empty hand" end
    if #objects == 0 then return true, "single item" end

    local entries = {}
    local function add_entry(object, ordinal)
        local metadata = item_metadata(object)
        if metadata.product_type ~= MOVIE_PRODUCT_TYPE then return false, "non-movie stack" end
        if metadata.genre == nil or metadata.sku == nil then return false, "missing movie metadata" end
        entries[#entries + 1] = {
            object = object,
            key = object_key(object),
            genre = metadata.genre,
            sku = metadata.sku,
            ordinal = ordinal,
        }
        return true, nil
    end

    local added, add_error = add_entry(held, 1)
    if not added then return false, add_error end
    for index, object in ipairs(objects) do
        added, add_error = add_entry(object, index + 1)
        if not added then return false, add_error end
    end

    table.sort(entries, function(first, second)
        if first.genre ~= second.genre then return first.genre < second.genre end
        if first.sku ~= second.sku then return first.sku < second.sku end
        return first.ordinal < second.ordinal
    end)

    local held_key = object_key(held)
    local held_index = nil
    for index, entry in ipairs(entries) do
        if entry.key == held_key then
            held_index = index
            break
        end
    end
    if not held_index then return false, "held object missing from sorted set" end

    local ordered = {}
    for offset = 1, #entries - 1 do
        local index = ((held_index - 1 + offset) % #entries) + 1
        ordered[#ordered + 1] = entries[index].object
    end
    if same_order(objects, ordered) then return true, "already sorted" end

    local written, write_error = write_array_order(inventory, ordered)
    if not written then return false, write_error end

    local reorganized, reorganize_error = invoke(player, "Reorganize Inventory")
    if not reorganized then return false, "Reorganize Inventory failed: " .. tostring(reorganize_error) end

    stats.sorts = stats.sorts + 1
    return true, "sorted"
end

local function state_matches(player, expected_held, expected_objects)
    local held, _, objects = collect_inventory(player)
    return object_key(held) == object_key(expected_held)
        and objects ~= nil
        and same_order(objects, expected_objects)
end

local function restore_post_scroll_state(player, expected_held, expected_objects)
    if state_matches(player, expected_held, expected_objects) then return true end

    local held, inventory, objects = collect_inventory(player)
    if not objects then return false end

    if valid_object(held) and object_key(held) == object_key(expected_held) then
        local written = write_array_order(inventory, expected_objects)
        if written then invoke(player, "Reorganize Inventory") end
        return state_matches(player, expected_held, expected_objects)
    end

    if valid_object(held) then
        local stashed = invoke(player, "Move Object From Hand To Inventory Stack")
        if not stashed then return false end
    end

    local empty_held, full_inventory, full_order = collect_inventory(player)
    if valid_object(empty_held) or not full_order then return false end
    if #full_order ~= #expected_objects + 1 then return false end

    local desired_full_order = { expected_held }
    for _, object in ipairs(expected_objects) do
        desired_full_order[#desired_full_order + 1] = object
    end

    local written = write_array_order(full_inventory, desired_full_order)
    if not written then return false end
    local restored = invoke(player, "Move Object From Inventory Stack To Hand")
    if not restored then return false end
    invoke(player, "Reorganize Inventory")
    return state_matches(player, expected_held, expected_objects)
end

local function reverse_completed_scroll(player)
    local held, _, objects, collect_error = collect_inventory(player)
    if not valid_object(held) or not objects then return false, collect_error or "empty hand" end
    if #objects <= 1 then return true, "two-item cycle needs no correction" end

    local expected_signature = inventory_signature(held, objects)
    if not expected_signature then return false, "invalid object in stack" end

    local stashed, stash_error = invoke(player, "Move Object From Hand To Inventory Stack")
    if not stashed then
        local recovered = restore_post_scroll_state(player, held, objects)
        return false, "failed to stash held object: " .. tostring(stash_error)
            .. (recovered and "; original state restored" or "; original state recovery failed")
    end

    local empty_held, inventory, full_order, full_error = collect_inventory(player)
    if valid_object(empty_held) or not full_order
        or #full_order ~= #objects + 1
        or inventory_signature(empty_held, full_order) ~= expected_signature then
        local recovered = restore_post_scroll_state(player, held, objects)
        return false, (full_error or "stash postcondition failed")
            .. (recovered and "; original state restored" or "; original state recovery failed")
    end

    local total = #full_order
    local start_index = total - 2
    local ordered = {}
    for offset = 0, total - 1 do
        local index = ((start_index - 1 + offset) % total) + 1
        ordered[#ordered + 1] = full_order[index]
    end

    local written, write_error = write_array_order(inventory, ordered)
    if not written then
        local recovered = restore_post_scroll_state(player, held, objects)
        return false, "reverse reorder failed: " .. tostring(write_error)
            .. (recovered and "; original state restored" or "; original state recovery failed")
    end

    local restored, restore_error = invoke(player, "Move Object From Inventory Stack To Hand")
    if not restored then
        local recovered = restore_post_scroll_state(player, held, objects)
        return false, "failed to restore hand: " .. tostring(restore_error)
            .. (recovered and "; original state restored" or "; original state recovery failed")
    end

    local reorganized, reorganize_error = invoke(player, "Reorganize Inventory")
    local expected_held = ordered[1]
    local expected_objects = {}
    for index = 2, #ordered do expected_objects[#expected_objects + 1] = ordered[index] end
    if not reorganized or not state_matches(player, expected_held, expected_objects) then
        local recovered = restore_post_scroll_state(player, held, objects)
        return false, "reverse postcondition failed: " .. tostring(reorganize_error)
            .. (recovered and "; original state restored" or "; original state recovery failed")
    end

    stats.reverse_scrolls = stats.reverse_scrolls + 1
    return true, "reversed"
end

local function schedule_state_update(player, sort_if_changed, reason)
    player = unwrap(player)
    state_generation = state_generation + 1
    local generation = state_generation

    execute_after_delay(tonumber(Config.InventorySettleMs) or 100, function()
        if generation ~= state_generation then return end

        local signature = membership_signature(player)
        local changed = signature ~= nil and signature ~= last_membership_signature
        if signature ~= nil then last_membership_signature = signature end

        if changed and sort_if_changed and Config.SortMoviesByGenre ~= false then
            local sorted, sort_result = sort_movie_inventory(player)
            if not sorted then
                stats.sort_skips = stats.sort_skips + 1
                if Config.DebugLogging == true then log("sort skipped: " .. tostring(sort_result)) end
            elseif Config.DebugLogging == true then
                log("sort result: " .. tostring(sort_result))
            end
        end

        last_stack_sequence = stack_sequence(player)
        last_sequence_membership_signature = signature
        if Config.AutoDumpAfterInventoryChange == true then dump_inventory(player, reason) end
    end)
end

local function after_add_to_hand(context)
    schedule_state_update(context, true, "Add object to Hand")
end

local function after_remove_from_hand(context)
    schedule_state_update(context, false, "Remove object to Hand")
end

local function after_scroll(context, direction)
    if adjusting_scroll then return end
    local numeric_direction = number_value(direction)
    local player = unwrap(context)
    local current_sequence = stack_sequence(player)
    local vanilla_completed = is_forward_rotation(last_stack_sequence, current_sequence)

    if numeric_direction ~= nil and numeric_direction < 0
        and Config.BidirectionalScroll ~= false and vanilla_completed then
        adjusting_scroll = true
        local ok, adjusted, adjust_result = pcall(reverse_completed_scroll, player)
        adjusting_scroll = false

        if not ok then
            log("reverse scroll failed: " .. tostring(adjusted))
        elseif not adjusted then
            log("reverse scroll failed: " .. tostring(adjust_result))
        elseif Config.DebugLogging == true then
            log("reverse scroll result: " .. tostring(adjust_result))
        end
    elseif numeric_direction ~= nil and numeric_direction < 0
        and Config.BidirectionalScroll ~= false and Config.DebugLogging == true then
        log("reverse scroll skipped: vanilla forward transition was not confirmed")
    end

    last_stack_sequence = stack_sequence(player)
end

local function hook_callback(label)
    if label == "Add object to Hand" then return after_add_to_hand end
    if label == "Remove object to Hand" then return after_remove_from_hand end
    return after_scroll
end

local function registered_hook_count()
    local count = 0
    for _ in pairs(registered_hooks) do count = count + 1 end
    return count
end

local function register_hooks()
    for _, hook in ipairs(hooks) do
        if not registered_hooks[hook.path] then
            local ok, pre_id, post_id = pcall(function()
                return RegisterHook(hook.path, hook_callback(hook.label))
            end)
            if ok and (pre_id ~= nil or post_id ~= nil) then
                registered_hooks[hook.path] = true
            end
        end
    end

    return registered_hook_count() == #hooks
end

local function setup_hooks()
    if register_hooks() then
        log(string.format("hooks registered: %d/%d", registered_hook_count(), #hooks))
        return
    end

    local function retry()
        execute_after_delay(tonumber(Config.HookRetryIntervalMs) or 1000, function()
            hook_retry_attempts = hook_retry_attempts + 1
            if register_hooks() then
                log(string.format("hooks registered: %d/%d", registered_hook_count(), #hooks))
            elseif hook_retry_attempts < (tonumber(Config.MaxHookRetryAttempts) or 120) then
                retry()
            else
                log(string.format("hook registration timed out: %d/%d", registered_hook_count(), #hooks))
            end
        end)
    end
    retry()
end

local function poll_inventory_baseline(delay_ms)
    execute_after_delay(delay_ms, function()
        local player = find_player()
        if player then
            local signature = membership_signature(player)
            if signature ~= nil and signature ~= last_sequence_membership_signature then
                last_stack_sequence = stack_sequence(player)
                last_sequence_membership_signature = signature
            end
            if not baseline_initialized then
                if state_generation == 0 then last_membership_signature = signature end
                baseline_initialized = true
                if Config.DebugLogging == true then log("initial inventory baseline captured") end
            end
        end

        poll_inventory_baseline(tonumber(Config.BaselinePollIntervalMs) or 1000)
    end)
end

RegisterConsoleCommandHandler("betterhandinventory", function(_, parameters, output)
    local command = parameters[1] and tostring(parameters[1]):lower() or "status"
    local message = nil

    if command == "dump" then
        message = dump_inventory(nil, "console") and "inventory dumped" or "inventory dump failed"
    elseif command == "sort" then
        local player = find_player()
        if player then
            local sorted, result = sort_movie_inventory(player)
            if sorted then
                last_membership_signature = membership_signature(player)
                last_stack_sequence = stack_sequence(player)
                last_sequence_membership_signature = last_membership_signature
            end
            message = "manual sort: " .. tostring(result)
        else
            message = "manual sort failed: player not found"
        end
    elseif command == "status" then
        message = string.format(
            "hooks=%d/%d bidirectional=%s sorting=%s reverse-scrolls=%d sorts=%d skips=%d retries=%d",
            registered_hook_count(),
            #hooks,
            Config.BidirectionalScroll == false and "OFF" or "ON",
            Config.SortMoviesByGenre == false and "OFF" or "ON",
            stats.reverse_scrolls,
            stats.sorts,
            stats.sort_skips,
            hook_retry_attempts
        )
    else
        message = "usage: betterhandinventory [status|dump|sort]"
    end

    log(message)
    if output ~= nil then pcall(function() output:Log("[BetterHandInventory] " .. message) end) end
    return true
end)

setup_hooks()
poll_inventory_baseline(tonumber(Config.InitialStateDelayMs) or 2500)
log("ready; run 'betterhandinventory status' in the console")
