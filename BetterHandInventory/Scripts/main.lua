local Config = require("config")
local InventoryModel = require("inventory_model")

local MOD_NAME = "BetterHandInventory"
local IS_PLUS = Config.Edition == "Plus"
local plus_controller = nil
local baseline_initialized = false
local last_membership_signature = nil
local stats = {
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
    local ok, has_get = pcall(function() return type(value.get) == "function" end)
    if not ok or not has_get then return value end
    local get_ok, result = pcall(function() return value:get() end)
    if get_ok then return result end
    return nil
end

local function valid_object(object)
    object = unwrap(object)
    if object == nil then return false end
    local ok, valid = pcall(function() return object:IsValid() end)
    return ok and valid == true
end

local function read_member(value, member_name)
    value = unwrap(value)
    if value == nil then return nil end
    local ok, member = pcall(function() return unwrap(value[member_name]) end)
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
    local ok, address = pcall(function() return object:GetAddress() end)
    if ok then return tostring(address) end
    return tostring(object)
end

local function describe_object(object)
    object = unwrap(object)
    if not valid_object(object) then return "nil" end
    local ok, full_name = pcall(function() return object:GetFullName() end)
    if ok and type(full_name) == "string" then return full_name end
    return tostring(object)
end

local function scalar(value)
    value = unwrap(value)
    if value == nil then return "nil" end
    local ok, text = pcall(function() return value:ToString() end)
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
        return object[function_name](object, table.unpack(arguments, 1, argument_count))
    end)
    if not ok then return false, result end
    return true, unwrap(result)
end

local function find_player()
    local ok, player = pcall(function() return FindFirstOf("Player_Character_C") end)
    player = unwrap(player)
    if ok and valid_object(player) then return player end
    return nil
end

local function array_size(array)
    if array == nil then return nil end
    local ok, size = pcall(function() return array:GetArrayNum() end)
    if ok then return tonumber(size) end
    ok, size = pcall(function() return #array end)
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
        inventory:ForEach(function(index, element) objects[index] = unwrap(element) end)
    end)
    if not ok then return held, inventory, nil, tostring(iteration_error) end
    if #objects ~= count then
        return held, inventory, nil, string.format("array count mismatch: %d/%d", #objects, count)
    end
    return held, inventory, objects, nil
end

local function execute_after_delay(delay_ms, callback)
    ExecuteWithDelay(delay_ms, function()
        local queued, queue_error = pcall(function() ExecuteInGameThread(callback) end)
        if not queued then log("failed to queue game-thread callback: " .. tostring(queue_error)) end
    end)
end

local function collect_array(array)
    local count = array_size(array)
    if count == nil then return nil, "array unavailable" end
    local objects = {}
    local ok, iteration_error = pcall(function()
        array:ForEach(function(index, element) objects[index] = unwrap(element) end)
    end)
    if not ok then return nil, tostring(iteration_error) end
    if #objects ~= count then
        return nil, string.format("array count mismatch: %d/%d", #objects, count)
    end
    return objects, nil
end

local function same_order(first, second)
    if #first ~= #second then return false end
    for index = 1, #first do
        if object_key(first[index]) ~= object_key(second[index]) then return false end
    end
    return true
end

local function write_array_slots(inventory, ordered)
    return pcall(function()
        inventory:ForEach(function(index, element) element:set(ordered[index]) end)
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

local function membership_signature(player)
    local held, _, objects = collect_inventory(player)
    if not objects then return nil end
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

local function sort_movie_inventory(player)
    local held, inventory, objects, collect_error = collect_inventory(player)
    if not valid_object(held) or not objects then return false, collect_error or "empty hand" end
    if #objects == 0 then return true, "single item" end

    local sequence = {}
    local function add_entry(object)
        local metadata = item_metadata(object)
        if metadata.product_type ~= MOVIE_PRODUCT_TYPE then return false, "non-movie stack" end
        sequence[#sequence + 1] = {
            id = object_key(object),
            genre = metadata.genre,
            sku = metadata.sku,
            object = object,
        }
        return true, nil
    end

    local added, add_error = add_entry(held)
    if not added then return false, add_error end
    for _, object in ipairs(objects) do
        added, add_error = add_entry(object)
        if not added then return false, add_error end
    end

    local ordered, order_error = InventoryModel.order_movies(sequence)
    if not ordered then return false, order_error end
    local ordered_inventory = {}
    for index = 2, #ordered do ordered_inventory[#ordered_inventory + 1] = ordered[index].object end
    if same_order(objects, ordered_inventory) then return true, "already sorted" end

    local written, write_error = write_array_order(inventory, ordered_inventory)
    if not written then return false, write_error end
    local reorganized, reorganize_error = invoke(player, "Reorganize Inventory")
    if not reorganized then
        local rolled_back = write_array_order(inventory, objects)
        if rolled_back then invoke(player, "Reorganize Inventory") end
        return false, "Reorganize Inventory failed: " .. tostring(reorganize_error)
            .. (rolled_back and "; original order restored" or "; rollback failed")
    end
    stats.sorts = stats.sorts + 1
    return true, "sorted"
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
    if not player then log("inventory dump skipped: player not found") return false end
    local held, _, objects, collect_error = collect_inventory(player)
    if not objects then log("inventory dump failed: " .. tostring(collect_error)) return false end
    log(string.format("inventory dump reason=%s stack=%d", tostring(reason), #objects))
    log_item("held", held)
    for index, object in ipairs(objects) do log_item(string.format("stack[%d]", index), object) end
    return true
end

local function poll_inventory(delay_ms)
    execute_after_delay(delay_ms, function()
        local player = not (plus_controller and plus_controller:is_incompatible()) and find_player() or nil
        if player then
            if plus_controller then plus_controller:poll(player) end
            local signature = membership_signature(player)
            local changed = baseline_initialized and signature ~= nil
                and signature ~= last_membership_signature

            if changed and Config.SortMoviesByGenre ~= false then
                local sorted, sort_result = sort_movie_inventory(player)
                if not sorted then
                    stats.sort_skips = stats.sort_skips + 1
                    if Config.DebugLogging == true then log("sort skipped: " .. tostring(sort_result)) end
                elseif Config.DebugLogging == true then
                    log("sort result: " .. tostring(sort_result))
                end
                signature = membership_signature(player)
            end
            if changed and Config.AutoDumpAfterInventoryChange == true then
                dump_inventory(player, "membership changed")
            end
            if signature ~= nil then last_membership_signature = signature end
            if not baseline_initialized then
                baseline_initialized = true
                if Config.DebugLogging == true then log("initial inventory baseline captured") end
            end
        end
        poll_inventory(tonumber(Config.BaselinePollIntervalMs) or 1000)
    end)
end

RegisterConsoleCommandHandler("betterhandinventory", function(_, parameters, output)
    local command = parameters[1] and tostring(parameters[1]):lower() or "status"
    local message
    if command == "dump" then
        message = dump_inventory(nil, "console") and "inventory dumped" or "inventory dump failed"
    elseif command == "sort" then
        local player = not (plus_controller and plus_controller:is_incompatible()) and find_player() or nil
        if player then
            local sorted, result = sort_movie_inventory(player)
            if sorted then last_membership_signature = membership_signature(player) end
            message = "manual sort: " .. tostring(result)
        else
            message = "manual sort failed: player not found"
        end
    elseif command == "status" then
        local plus_status = plus_controller and plus_controller:status() or "standard"
        message = string.format(
            "edition=%s hooks=0 bidirectional=NATIVE sorting=%s sorts=%d skips=%d plus=%s",
            IS_PLUS and "Plus" or "Standard",
            Config.SortMoviesByGenre == false and "OFF" or "ON",
            stats.sorts,
            stats.sort_skips,
            plus_status
        )
    else
        message = "usage: betterhandinventory [status|dump|sort]"
    end
    log(message)
    if output ~= nil then pcall(function() output:Log("[BetterHandInventory] " .. message) end) end
    return true
end)

if IS_PLUS then
    local Plus = require("plus")
    plus_controller = Plus.new({
        config = Config,
        log = log,
        unwrap = unwrap,
        valid_object = valid_object,
        read_member = read_member,
        number_value = number_value,
        object_key = object_key,
        describe_object = describe_object,
        item_metadata = item_metadata,
        invoke = invoke,
        find_player = find_player,
        collect_inventory = collect_inventory,
        execute_after_delay = execute_after_delay,
    })
    plus_controller:start()
end

if IS_PLUS or Config.SortMoviesByGenre ~= false or Config.AutoDumpAfterInventoryChange == true then
    poll_inventory(tonumber(Config.InitialStateDelayMs) or 2500)
end
log("ready; run 'betterhandinventory status' in the console")
