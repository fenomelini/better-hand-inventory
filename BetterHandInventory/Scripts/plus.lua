local Plus = {}

local CONTAINER_REF = "Container where Pickup Actor is Stored"
local CONTAINER_OWNER = "Object owning of this container"
local SHELF_CONTAINERS = "All Selve Containers"
local CURRENTLY_IN_HAND = "Currently in Hand"
local CAN_BE_PICKED_UP = "Can be pick up"
local NORMAL_SHELF_CONTAINER_CLASS = "Shelve_Container_C"
local OUT_FOR_RENT = "Out for Rent"
local DAY_END_HOOK = "/Game/VideoStore/core/gamemode/Core_Gamemode.Core_Gamemode_C:End of the day"

local DELIVERY_CENTER = { X = 2237.0, Y = -2709.0, Z = 62.0 }
local GRID_COLUMNS = 5
local GRID_ROWS = 2
local GRID_COLUMN_STEP = 16.0
local GRID_ROW_STEP = 25.0
local GRID_LAYER_STEP = 6.0
local GRID_ORIGIN_X = 61.0
local GRID_ORIGIN_Y = -24.0
local GRID_ORIGIN_Z = 7.0

local KEY_MAP = {
    F1 = Key.F1,
    F2 = Key.F2,
    F3 = Key.F3,
    F4 = Key.F4,
    F5 = Key.F5,
    F6 = Key.F6,
    F7 = Key.F7,
    F8 = Key.F8,
    F9 = Key.F9,
    F10 = Key.F10,
    F11 = Key.F11,
    F12 = Key.F12,
}

local function distance(first, second)
    local dx = first.X - second.X
    local dy = first.Y - second.Y
    local dz = first.Z - second.Z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function Plus.new(api)
    local normal_shelf_container_class = nil
    local self = {
        api = api,
        config = api.config,
        marked = {},
        marked_skus = {},
        keybinds_registered = false,
        lifecycle_hook_registered = false,
        blocked_logged = false,
        permanently_blocked = false,
        player_key = nil,
        action_running = false,
        stats = {
            boxes = 0,
            marked = 0,
            collected = 0,
        },
    }

    local function debug(message)
        if self.config.DebugLogging == true then api.log("Plus: " .. message) end
    end

    local function read_status(object, member_name)
        object = api.unwrap(object)
        if object == nil then return false, nil end
        local ok, value = pcall(function()
            return api.unwrap(object[member_name])
        end)
        if not ok then return false, nil end
        return true, value
    end

    local function find_all(class_name)
        local ok, objects = pcall(function()
            return FindAllOf(class_name)
        end)
        if not ok or objects == nil then return {} end
        return objects
    end

    local function is_normal_shelf_container(object)
        object = api.unwrap(object)
        if not api.valid_object(object) then return false end
        if not api.valid_object(normal_shelf_container_class) then
            local ok, instance = pcall(function()
                return FindFirstOf(NORMAL_SHELF_CONTAINER_CLASS)
            end)
            instance = api.unwrap(instance)
            if not ok or not api.valid_object(instance) then return false end
            local class_ok, resolved_class = pcall(function() return instance:GetClass() end)
            if not class_ok or not api.valid_object(resolved_class) then return false end
            normal_shelf_container_class = resolved_class
        end
        local ok, matches = pcall(function()
            return object:IsA(normal_shelf_container_class)
        end)
        return ok and matches == true
    end

    local function gather_cartridges()
        local gatherers = find_all("ActorGatherer_C")
        local gatherer = nil
        for _, candidate in pairs(gatherers) do gatherer = candidate break end
        if not api.valid_object(gatherer) then return nil, "actor gatherer unavailable" end
        local map_ok, cartridge_map = read_status(gatherer, "Cartridge Map")
        if not map_ok or cartridge_map == nil then return nil, "cartridge map unavailable" end
        local cartridges = {}
        local iterated = pcall(function()
            cartridge_map:ForEach(function(_, value)
                local cartridge = api.unwrap(value)
                if api.valid_object(cartridge) then cartridges[#cartridges + 1] = cartridge end
            end)
        end)
        if not iterated then return nil, "cartridge map iteration failed" end
        return cartridges, nil
    end

    local function each_array(array, callback)
        if array == nil then return false end
        return pcall(function()
            array:ForEach(function(_, value)
                callback(api.unwrap(value))
            end)
        end)
    end

    local function add_object(set, object)
        local key = api.object_key(object)
        if key then set[key] = api.unwrap(object) end
        return key
    end

    local function build_player_exclusions(player)
        local excluded = {}
        local held, _, inventory, inventory_error = api.collect_inventory(player)
        if not inventory then return nil, inventory_error or "inventory unavailable" end
        if api.valid_object(held) then add_object(excluded, held) end
        for _, object in ipairs(inventory) do
            if api.valid_object(object) then add_object(excluded, object) end
        end
        return excluded, nil
    end

    local function collect_shelf_containers(class_name)
        local containers = {}
        for _, shelf in ipairs(find_all(class_name)) do
            if api.valid_object(shelf) then
                local ok, shelf_containers = read_status(shelf, SHELF_CONTAINERS)
                if not ok or not each_array(shelf_containers, function(container)
                    if api.valid_object(container) then add_object(containers, container) end
                end) then
                    return nil, "shelf container snapshot failed"
                end
            end
        end
        return containers, nil
    end

    local function build_shelf_state()
        local reserved, reserved_error = collect_shelf_containers("Reserved_C")
        if not reserved then return nil, reserved_error end
        return { reserved = reserved }, nil
    end

    local function object_flag_is_false(object, property_name)
        local ok, value = read_status(object, property_name)
        return ok and value == false
    end

    local function eligible_shelf_cartridge(cartridge, sku, excluded, shelves)
        if not api.valid_object(cartridge) then return false, nil end
        local key = api.object_key(cartridge)
        if not key or excluded[key] then return false, nil end

        local metadata = api.item_metadata(cartridge)
        if metadata.product_type ~= 1 or metadata.sku ~= sku then return false, nil end

        local container_ok, container = read_status(cartridge, CONTAINER_REF)
        if not container_ok or not api.valid_object(container) then return false, nil end
        if not is_normal_shelf_container(container) then return false, nil end
        local container_key = api.object_key(container)
        if not container_key or shelves.reserved[container_key] then
            return false, nil
        end

        local owner_ok, owner = read_status(container, CONTAINER_OWNER)
        if not owner_ok or api.object_key(owner) ~= key then return false, nil end
        if not object_flag_is_false(cartridge, CURRENTLY_IN_HAND) then return false, nil end
        if not object_flag_is_false(cartridge, OUT_FOR_RENT) then return false, nil end
        return true, container
    end

    local function set_marker(cartridge, visible)
        if not visible then return api.invoke(cartridge, "PlayerIsNOTLookingAt") == true end
        local initialized = api.invoke(cartridge, "PlayerIsLookingAt")
        if not initialized then return false end
        api.invoke(cartridge, "PlayerIsNOTLookingAt")
        return api.invoke(cartridge, "Widget Visibility", true) == true
    end

    local function update_stats()
        local parts = {
            "Delivery boxes retrieved=" .. self.stats.boxes,
            "Shelf matches active=" .. self.stats.marked,
            "Shelf tapes moved=" .. self.stats.collected,
        }
        pcall(function()
            local contributors = ModRef:GetSharedVariable("StatHead::Contributors") or ""
            if not contributors:find("Better Hand Inventory Plus;", 1, true) then
                ModRef:SetSharedVariable(
                    "StatHead::Contributors",
                    contributors .. "Better Hand Inventory Plus;"
                )
            end
            ModRef:SetSharedVariable(
                "StatHead::Data::Better Hand Inventory Plus",
                table.concat(parts, "|")
            )
        end)
    end

    local function recount_marks()
        local count = 0
        for _ in pairs(self.marked) do count = count + 1 end
        self.stats.marked = count
    end

    local function remove_mark(key)
        local entry = self.marked[key]
        if not entry then return end
        if api.valid_object(entry.object) then set_marker(entry.object, false) end
        self.marked[key] = nil
        recount_marks()
    end

    local function clear_sku(sku)
        for key, entry in pairs(self.marked) do
            if entry.sku == sku then remove_mark(key) end
        end
        self.marked_skus[sku] = nil
        update_stats()
    end

    local function clear_all_marks()
        for key in pairs(self.marked) do remove_mark(key) end
        self.marked_skus = {}
        update_stats()
    end

    local function prepare_for_world_transition()
        clear_all_marks()
        self.player_key = nil
        self.action_running = false
        api.log("Plus: world transition detected; tape references cleared")
    end

    local function setup_world_transition_hook(attempt)
        api.execute_after_delay(attempt == 0 and 0 or 1000, function()
            if self.lifecycle_hook_registered then return end
            local ok = pcall(function()
                RegisterHook(DAY_END_HOOK, prepare_for_world_transition)
            end)
            if ok then
                self.lifecycle_hook_registered = true
                debug("world-transition hook registered")
            elseif attempt < 120 then
                setup_world_transition_hook(attempt + 1)
            else
                api.log("Plus: world-transition hook registration timed out")
            end
        end)
    end

    local function mark_current_sku()
        if self:is_incompatible() then return end
        local player = api.find_player()
        if not player then api.log("Plus: player not found") return end
        local held = api.read_member(player, "Object Hold")
        local metadata = api.item_metadata(held)
        if metadata.product_type ~= 1 or metadata.sku == nil then
            api.log("Plus: hold a movie cassette before marking")
            return
        end
        if self.marked_skus[metadata.sku] then
            clear_sku(metadata.sku)
            api.log("Plus: matching tapes unmarked")
            return
        end

        local shelves, shelf_error = build_shelf_state()
        if not shelves then api.log("Plus: marking aborted: " .. tostring(shelf_error)) return end
        local cartridges, gather_error = gather_cartridges()
        if not cartridges then api.log("Plus: marking aborted: " .. tostring(gather_error)) return end
        local count = 0
        for _, cartridge in ipairs(cartridges) do
            local eligible, container = eligible_shelf_cartridge(
                    cartridge,
                    metadata.sku,
                    {},
                    shelves
                )
            if eligible then
                local key = api.object_key(cartridge)
                if set_marker(cartridge, true) then
                    self.marked[key] = {
                        object = api.unwrap(cartridge),
                        container = container,
                        sku = metadata.sku,
                    }
                    count = count + 1
                end
            end
        end

        if count == 0 then
            api.log("Plus: no eligible shelf copies found")
            return
        end
        self.marked_skus[metadata.sku] = true
        recount_marks()
        update_stats()
        api.log(string.format("Plus: marked %d shelf cassette(s)", count))
    end

    local function actor_location(actor)
        local ok, location = pcall(function()
            return actor:K2_GetActorLocation()
        end)
        return ok and location or nil
    end

    local function actor_rotation(actor)
        local ok, rotation = pcall(function()
            return actor:K2_GetActorRotation()
        end)
        return ok and rotation or nil
    end

    local function move_actor(actor, location, rotation)
        if not api.valid_object(actor) then return false end
        local physics_disabled = api.invoke(actor, "Toggle Simulate Physic", false)
        if not physics_disabled then return false end
        local function fail()
            api.invoke(actor, "Toggle Simulate Physic", true)
            return false
        end
        local ok, location_result, rotation_result = pcall(function()
            local moved = actor:K2_SetActorLocation(location, false, {}, true)
            local rotated = actor:K2_SetActorRotation(rotation, true)
            return moved, rotated
        end)
        if not ok or location_result == false or rotation_result == false then return fail() end
        local final_location = actor_location(actor)
        if final_location == nil or distance(final_location, location) > 2.0 then return fail() end
        return true
    end

    local function enable_loose_physics(actor)
        if not api.valid_object(actor) then return false end
        local container_ok, container = read_status(actor, CONTAINER_REF)
        if not container_ok or api.valid_object(container) then return false end
        local state_written = pcall(function()
            actor[CURRENTLY_IN_HAND] = false
            actor[CAN_BE_PICKED_UP] = true
        end)
        local hand_ok, in_hand = read_status(actor, CURRENTLY_IN_HAND)
        local pickup_ok, can_be_picked_up = read_status(actor, CAN_BE_PICKED_UP)
        if not state_written or not hand_ok or in_hand ~= false
            or not pickup_ok or can_be_picked_up ~= true then
            api.log(string.format(
                "Plus: loose-state restore failed written=%s in_hand=%s can_pickup=%s",
                tostring(state_written),
                tostring(in_hand),
                tostring(can_be_picked_up)
            ))
            return false
        end
        return api.invoke(actor, "Toggle Simulate Physic", true) == true
    end

    local function grid_location(origin, slot)
        local floor_size = GRID_COLUMNS * GRID_ROWS
        local layer = math.floor(slot / floor_size)
        local floor_slot = slot % floor_size
        local row = math.floor(floor_slot / GRID_COLUMNS)
        local column = floor_slot % GRID_COLUMNS
        return {
            X = origin.X + GRID_ORIGIN_X + column * GRID_COLUMN_STEP,
            Y = origin.Y + GRID_ORIGIN_Y + row * GRID_ROW_STEP,
            Z = origin.Z + GRID_ORIGIN_Z + layer * GRID_LAYER_STEP,
        }
    end

    local function loose_pad_candidate(cartridge, excluded, origin)
        if not api.valid_object(cartridge) then return false end
        local key = api.object_key(cartridge)
        if not key or excluded[key] or self.marked[key] then return false end
        local container_ok, container = read_status(cartridge, CONTAINER_REF)
        if not container_ok or api.valid_object(container) then return false end
        if not object_flag_is_false(cartridge, CURRENTLY_IN_HAND) then return false end
        if not object_flag_is_false(cartridge, OUT_FOR_RENT) then return false end
        local location = actor_location(cartridge)
        if not location then return false end
        return math.abs(location.X - (origin.X + 90.0)) <= 100.0
            and math.abs(location.Y - origin.Y) <= 80.0
            and math.abs(location.Z - origin.Z) <= 100.0
    end

    local function restore_shelf_pair(cartridge, container)
        if not api.valid_object(cartridge) or not api.valid_object(container) then return false end
        local cartridge_key = api.object_key(cartridge)
        local container_key = api.object_key(container)
        if not cartridge_key or not container_key then return false end
        local owner_ok, owner = read_status(container, CONTAINER_OWNER)
        local container_ok, current_container = read_status(cartridge, CONTAINER_REF)
        if not owner_ok or not container_ok then return false end
        local owner_key = api.object_key(owner)
        local current_container_key = api.object_key(current_container)
        if owner_key and owner_key ~= cartridge_key then return false end
        if current_container_key and current_container_key ~= container_key then return false end
        if not api.invoke(
            container,
            "Store Object From Game Code And No Animation",
            cartridge,
            true
        ) then
            return false
        end
        owner_ok, owner = read_status(container, CONTAINER_OWNER)
        container_ok, current_container = read_status(cartridge, CONTAINER_REF)
        return owner_ok and container_ok
            and api.object_key(owner) == cartridge_key
            and api.object_key(current_container) == container_key
    end

    local function release_from_shelf(cartridge, container)
        if not api.valid_object(cartridge) or not api.valid_object(container) then return false end
        local cartridge_key = api.object_key(cartridge)
        if not cartridge_key
            or api.object_key(api.read_member(container, CONTAINER_OWNER)) ~= cartridge_key then
            return false
        end
        local told = api.invoke(cartridge, "Tell Container this object is no longer stored")
        local owner_read, remaining_owner = read_status(container, CONTAINER_OWNER)
        local final_container_read, final_container = read_status(cartridge, CONTAINER_REF)
        local released = told and owner_read and final_container_read
            and not api.valid_object(remaining_owner)
            and not api.valid_object(final_container)
        if released then return true end
        if not restore_shelf_pair(cartridge, container) then
            api.log("Plus: shelf release rollback failed")
        end
        return false
    end

    local function find_world_pad()
        for _, pad in ipairs(find_all("TeleportCartridge_C")) do
            if api.valid_object(pad) then return api.unwrap(pad) end
        end
        return nil
    end

    local function collect_marked()
        if self:is_incompatible() then return end
        local player = api.find_player()
        if not player then api.log("Plus: player not found") return end
        local pad = find_world_pad()
        if not api.valid_object(pad) then api.log("Plus: return pad not found") return end
        local origin = actor_location(pad)
        if not origin then api.log("Plus: return pad location unavailable") return end
        local excluded, exclusion_error = build_player_exclusions(player)
        if not excluded then
            api.log("Plus: collection aborted: " .. tostring(exclusion_error))
            return
        end

        local cartridges, gather_error = gather_cartridges()
        if not cartridges then
            api.log("Plus: collection aborted: " .. tostring(gather_error))
            return
        end
        local recovered = 0
        for _, cartridge in ipairs(cartridges) do
            if loose_pad_candidate(cartridge, excluded, origin)
                and enable_loose_physics(cartridge) then
                recovered = recovered + 1
            end
        end
        if recovered > 0 then
            api.log(string.format("Plus: restored physics on %d return-pad cassette(s)", recovered))
        end

        local shelves, shelf_error = build_shelf_state()
        if not shelves then api.log("Plus: collection aborted: " .. tostring(shelf_error)) return end
        local capacity = math.floor(tonumber(self.config.CollectionCapacity) or 48)
        capacity = math.max(1, math.min(48, capacity))
        local pad_cassettes = {}
        if self.config.ReorganizeReturnPad ~= false then
            for _, cartridge in ipairs(cartridges) do
                if loose_pad_candidate(cartridge, excluded, origin) then
                    pad_cassettes[#pad_cassettes + 1] = api.unwrap(cartridge)
                end
            end
        end
        table.sort(pad_cassettes, function(first, second)
            return tostring(api.object_key(first)) < tostring(api.object_key(second))
        end)

        local slot = 0
        local moved = {}
        for _, cartridge in ipairs(pad_cassettes) do
            if slot >= capacity then break end
            local destination = grid_location(origin, slot)
            if move_actor(cartridge, destination, { Pitch = 0, Yaw = 0, Roll = -90 }) then
                moved[#moved + 1] = { object = cartridge, location = destination }
                slot = slot + 1
            end
        end

        local collected = 0
        local stale = {}
        for key, entry in pairs(self.marked) do
            if slot >= capacity then break end
            local eligible, container = eligible_shelf_cartridge(
                entry.object,
                entry.sku,
                excluded,
                shelves
            )
            if not eligible then
                stale[#stale + 1] = key
            elseif release_from_shelf(entry.object, container) then
                local destination = grid_location(origin, slot)
                if move_actor(
                    entry.object,
                    destination,
                    { Pitch = 0, Yaw = 0, Roll = -90 }
                ) then
                    moved[#moved + 1] = { object = entry.object, location = destination }
                    collected = collected + 1
                    slot = slot + 1
                    stale[#stale + 1] = key
                else
                    stale[#stale + 1] = key
                    if restore_shelf_pair(entry.object, container) then
                        api.log("Plus: a cassette move failed and was restored to its shelf")
                    else
                        enable_loose_physics(entry.object)
                        api.log("Plus: a released cassette could not be moved or restored")
                    end
                end
            else
                api.log("Plus: skipped a cassette because its shelf could not be released safely")
            end
        end

        for _, key in ipairs(stale) do remove_mark(key) end
        for sku in pairs(self.marked_skus) do
            local present = false
            for _, entry in pairs(self.marked) do
                if entry.sku == sku then present = true break end
            end
            if not present then self.marked_skus[sku] = nil end
        end

        for _, entry in ipairs(moved) do
            if not enable_loose_physics(entry.object) then
                api.log("Plus: could not restore physics on a moved cassette")
            end
        end

        self.stats.collected = self.stats.collected + collected
        update_stats()
        api.log(string.format(
            "Plus: collected %d cassette(s); reorganized %d; %d mark(s) remain",
            collected,
            #pad_cassettes,
            self.stats.marked
        ))
    end

    local function box_is_free(box, excluded)
        if not api.valid_object(box) then return false, "invalid" end
        local key = api.object_key(box)
        if not key then return false, "no address" end
        if excluded[key] then return false, "player inventory" end
        local container_ok, container = read_status(box, CONTAINER_REF)
        if not container_ok then return false, "container unavailable" end
        if api.valid_object(container) then return false, "stored in container" end
        local location = actor_location(box)
        if not location then return false, "location unavailable" end
        local delivery_distance = distance(location, DELIVERY_CENTER)
        if delivery_distance > (tonumber(self.config.DeliveryBoxMaxDistance) or 700) then
            return false, string.format("distance=%.1f", delivery_distance), delivery_distance
        end
        return true, "eligible", delivery_distance
    end

    local function grab_delivery_box()
        if self:is_incompatible() then return end
        local player = api.find_player()
        if not player then api.log("Plus: player not found") return end
        local excluded, exclusion_error = build_player_exclusions(player)
        if not excluded then api.log("Plus: box retrieval aborted: " .. tostring(exclusion_error)) return end
        local selected = nil
        local selected_distance = math.huge
        local boxes = find_all("MovingBox_C")
        debug(string.format("delivery box scan found %d candidate(s)", #boxes))
        for _, box in ipairs(boxes) do
            local eligible, reason, candidate_distance = box_is_free(box, excluded)
            debug(string.format(
                "delivery box %s: %s",
                tostring(api.object_key(box)),
                tostring(reason)
            ))
            if eligible then
                if candidate_distance < selected_distance then
                    selected = api.unwrap(box)
                    selected_distance = candidate_distance
                end
            end
        end
        if not selected then api.log("Plus: no free delivery box found") return end

        local player_location = actor_location(player)
        local player_rotation = actor_rotation(player)
        if not player_location or not player_rotation then
            api.log("Plus: player transform unavailable")
            return
        end
        local yaw = math.rad(player_rotation.Yaw or 0)
        local destination = {
            X = player_location.X + math.cos(yaw) * 90.0,
            Y = player_location.Y + math.sin(yaw) * 90.0,
            Z = player_location.Z + 45.0,
        }
        if not move_actor(selected, destination, { Pitch = 0, Yaw = player_rotation.Yaw or 0, Roll = 0 }) then
            api.log("Plus: delivery box move failed")
            return
        end
        if api.invoke(selected, "Toggle Simulate Physic", true) ~= true then
            api.log("Plus: delivery box physics restore failed")
            return
        end
        self.stats.boxes = self.stats.boxes + 1
        update_stats()
        api.log("Plus: delivery box moved in front of the player")
    end

    local function run_action(callback)
        if self.action_running then
            debug("action ignored while another Plus action is running")
            return
        end
        self.action_running = true
        local ok, error_message = pcall(callback)
        self.action_running = false
        if not ok then api.log("Plus: action failed: " .. tostring(error_message)) end
    end

    function self:is_incompatible()
        if self.permanently_blocked then return true end
        local ok, contributors = pcall(function()
            return ModRef:GetSharedVariable("StatHead::Contributors")
        end)
        local blocked = ok and type(contributors) == "string"
            and contributors:find("Inventory QoL;", 1, true) ~= nil
        if not blocked then
            local data_ok, data = pcall(function()
                return ModRef:GetSharedVariable("StatHead::Data::Inventory QoL")
            end)
            blocked = data_ok and type(data) == "string"
        end
        if blocked and not self.blocked_logged then
            self.permanently_blocked = true
            self.blocked_logged = true
            api.log("Plus disabled: remove Inventory QoL and restart the game")
        end
        return blocked
    end

    function self:poll(player)
        if self:is_incompatible() or not api.valid_object(player) then return end
        local current_player_key = api.object_key(player)
        if self.player_key and self.player_key ~= current_player_key then
            clear_all_marks()
        end
        self.player_key = current_player_key

        local stale = {}
        for key, entry in pairs(self.marked) do
            if not api.valid_object(entry.object) then
                stale[#stale + 1] = key
            end
        end
        for _, key in ipairs(stale) do remove_mark(key) end
        if #stale > 0 then update_stats() end
    end

    function self:status()
        return string.format(
            "blocked=%s keys=%s lifecycle=%s marked=%d collected=%d boxes=%d",
            self:is_incompatible() and "YES" or "NO",
            self.keybinds_registered and "ON" or "OFF",
            self.lifecycle_hook_registered and "ON" or "OFF",
            self.stats.marked,
            self.stats.collected,
            self.stats.boxes
        )
    end

    function self:start()
        update_stats()
        setup_world_transition_hook(0)
        api.execute_after_delay(1000, function()
            if self:is_incompatible() then return end
            local requested = {}
            if self.config.GrabDeliveryBoxes ~= false then
                requested[#requested + 1] = {
                    name = self.config.GrabBoxKey or "F5",
                    action = grab_delivery_box,
                    label = "boxes",
                }
            end
            if self.config.MarkMatchingTapes ~= false then
                requested[#requested + 1] = {
                    name = self.config.MarkTapeKey or "F6",
                    action = mark_current_sku,
                    label = "mark",
                }
            end
            if self.config.CollectMarkedTapes ~= false then
                requested[#requested + 1] = {
                    name = self.config.CollectTapeKey or "F7",
                    action = collect_marked,
                    label = "collect",
                }
            end

            local failures = {}
            local seen = {}
            for _, binding in ipairs(requested) do
                binding.name = tostring(binding.name):upper()
                binding.key = KEY_MAP[binding.name]
                if not binding.key then
                    failures[#failures + 1] = "unsupported key " .. binding.name
                elseif seen[binding.name] then
                    failures[#failures + 1] = "duplicate key " .. binding.name
                else
                    seen[binding.name] = true
                    local check_ok, occupied = pcall(function()
                        return IsKeyBindRegistered(binding.key) == true
                    end)
                    if not check_ok or occupied then
                        failures[#failures + 1] = "key unavailable " .. binding.name
                    end
                end
            end

            if #requested == 0 then
                api.log("Plus loaded with all key actions disabled")
                return
            elseif #failures > 0 then
                api.log("Plus keybind registration aborted: " .. table.concat(failures, "; "))
                return
            end

            for _, binding in ipairs(requested) do
                local action = binding.action
                local registered, register_error = pcall(function()
                    RegisterKeyBind(binding.key, function()
                        if not self:is_incompatible() then run_action(action) end
                    end)
                end)
                if not registered then
                    api.log("Plus keybind registration failed: " .. tostring(register_error))
                    return
                end
            end
            self.keybinds_registered = true
            local labels = {}
            for _, binding in ipairs(requested) do
                labels[#labels + 1] = binding.name .. "=" .. binding.label
            end
            api.log("Plus ready: " .. table.concat(labels, ", "))
        end)
    end

    self.clear_all_marks = clear_all_marks
    return self
end

return Plus
