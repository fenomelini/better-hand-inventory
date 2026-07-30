package.path = "BetterHandInventory/Scripts/?.lua;" .. package.path

local Model = require("inventory_model")

local function assert_ids(actual, expected, label)
    assert(#actual == #expected, label .. ": size mismatch")
    for index, entry in ipairs(actual) do
        assert(entry.id == expected[index], string.format(
            "%s: index %d expected %s, got %s",
            label,
            index,
            tostring(expected[index]),
            tostring(entry.id)
        ))
    end
end

local function sequence(size)
    local result = {}
    for index = 1, size do
        result[index] = { id = index, genre = index % 3, sku = size - index }
    end
    return result
end

for size = 1, 10 do
    local original = sequence(size)
    local forward = original
    local reverse = original
    for _ = 1, size do
        forward = assert(Model.rotate(forward, 1))
        reverse = assert(Model.rotate(reverse, -1))
    end
    local expected = {}
    for index = 1, size do expected[index] = index end
    assert_ids(forward, expected, "forward cycle " .. size)
    assert_ids(reverse, expected, "reverse cycle " .. size)

    local next_sequence = assert(Model.rotate(original, 1))
    local restored = assert(Model.rotate(next_sequence, -1))
    assert_ids(restored, expected, "inverse rotations " .. size)

    if size > 1 then
        local vanilla_forward = assert(Model.exchange_held(original, 1, false))
        local expected_forward = assert(Model.rotate(original, 1))
        local forward_ids = {}
        for index, entry in ipairs(expected_forward) do forward_ids[index] = entry.id end
        assert_ids(vanilla_forward, forward_ids, "vanilla exchange " .. size)

        local corrected_reverse = assert(Model.exchange_held(original, size - 1, true))
        local expected_reverse = assert(Model.rotate(original, -1))
        local reverse_ids = {}
        for index, entry in ipairs(expected_reverse) do reverse_ids[index] = entry.id end
        assert_ids(corrected_reverse, reverse_ids, "corrected reverse exchange " .. size)
    end
end

local unordered_movies = {
    { id = "held", genre = 2, sku = 20 },
    { id = "late", genre = 3, sku = 30 },
    { id = "first", genre = 1, sku = 10 },
    { id = "same-a", genre = 2, sku = 20 },
    { id = "same-b", genre = 2, sku = 20 },
}
local ordered = assert(Model.order_movies(unordered_movies))
assert_ids(ordered, { "held", "same-a", "same-b", "late", "first" }, "movie order")
for _, entry in ipairs(unordered_movies) do
    assert(entry.ordinal == nil, "movie ordering must not mutate caller entries")
end

local invalid, duplicate_error = Model.rotate({ { id = 1 }, { id = 1 } }, 1)
assert(invalid == nil and duplicate_error:find("duplicate", 1, true), "duplicates must be rejected")

print("inventory_model_spec: ok")
