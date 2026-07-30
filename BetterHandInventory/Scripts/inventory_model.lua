local Model = {}

local function copy(sequence)
    local result = {}
    for index, value in ipairs(sequence) do result[index] = value end
    return result
end

function Model.validate(sequence)
    if type(sequence) ~= "table" or #sequence == 0 then
        return false, "empty sequence"
    end

    local seen = {}
    for index, entry in ipairs(sequence) do
        if type(entry) ~= "table" or entry.id == nil then
            return false, "missing item id at index " .. tostring(index)
        end
        if seen[entry.id] then return false, "duplicate item id " .. tostring(entry.id) end
        seen[entry.id] = true
    end
    return true, nil
end

function Model.rotate(sequence, direction)
    local valid, validation_error = Model.validate(sequence)
    if not valid then return nil, validation_error end
    if #sequence == 1 then return copy(sequence), nil end

    local result = {}
    if direction < 0 then
        result[1] = sequence[#sequence]
        for index = 1, #sequence - 1 do result[index + 1] = sequence[index] end
    else
        for index = 2, #sequence do result[index - 1] = sequence[index] end
        result[#sequence] = sequence[1]
    end
    return result, nil
end

function Model.exchange_held(sequence, inventory_index, move_old_held_to_front)
    local valid, validation_error = Model.validate(sequence)
    if not valid then return nil, validation_error end
    if #sequence == 1 then return copy(sequence), nil end
    if inventory_index < 1 or inventory_index >= #sequence then
        return nil, "inventory index out of range"
    end

    local selected_index = inventory_index + 1
    local result = { sequence[selected_index] }
    for index = 2, #sequence do
        if index ~= selected_index then result[#result + 1] = sequence[index] end
    end
    result[#result + 1] = sequence[1]

    if move_old_held_to_front then
        local old_held = table.remove(result)
        table.insert(result, 2, old_held)
    end
    return result, nil
end

function Model.order_movies(sequence)
    local valid, validation_error = Model.validate(sequence)
    if not valid then return nil, validation_error end

    local held_id = sequence[1].id
    local ordered = {}
    for index, entry in ipairs(sequence) do
        if entry.genre == nil or entry.sku == nil then
            return nil, "missing movie metadata at index " .. tostring(index)
        end
        local copied_entry = {}
        for key, value in pairs(entry) do copied_entry[key] = value end
        copied_entry.ordinal = index
        ordered[index] = copied_entry
    end

    table.sort(ordered, function(first, second)
        if first.genre ~= second.genre then return first.genre < second.genre end
        if first.sku ~= second.sku then return first.sku < second.sku end
        return first.ordinal < second.ordinal
    end)

    local held_index = nil
    for index, entry in ipairs(ordered) do
        if entry.id == held_id then held_index = index break end
    end
    if not held_index then return nil, "held item missing from sorted sequence" end

    local result = { ordered[held_index] }
    for offset = 1, #ordered - 1 do
        local index = ((held_index - 1 + offset) % #ordered) + 1
        result[#result + 1] = ordered[index]
    end
    return result, nil
end

return Model
