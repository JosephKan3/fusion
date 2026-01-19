-- AE2 Helper Module for Waterline Tier Controller
-- Provides functions to check item and fluid quantities in AE2 network

local component = require("component")

local AE2 = {}

-- ME Interface reference (set during init or auto-detected)
local ME = nil

-- Initialize the AE2 module with optional specific ME interface address
function AE2.init(meAddress)
    if meAddress then
        ME = component.proxy(meAddress)
    else
        ME = component.me_interface
    end

    if not ME then
        error("No ME Interface found! Please connect an ME Interface to the computer.")
    end

    return true
end

-- Get the amount of a specific fluid in the network
-- Returns the amount in mB, or 0 if not found
function AE2.getFluidAmount(fluidName)
    if not ME then
        AE2.init()
    end

    local fluids = ME.getFluidsInNetwork()
    if not fluids then
        return 0
    end

    local total = 0
    local targetLower = fluidName:lower()

    for _, fluid in pairs(fluids) do
        local label = fluid.label or ""
        if label:lower() == targetLower then
            total = total + (fluid.amount or 0)
        end
    end

    return total
end

-- Get the amount of a specific item in the network
-- Returns the stack size, or 0 if not found
function AE2.getItemAmount(itemName)
    if not ME then
        AE2.init()
    end

    local items = ME.getItemsInNetwork({ label = itemName })
    if not items then
        return 0
    end

    local total = 0
    for _, item in pairs(items) do
        total = total + (item.size or 0)
    end

    return total
end

-- Check if the required amount of an item or fluid exists
-- Returns: hasEnough (boolean), currentAmount (number)
function AE2.checkRequirement(name, requiredAmount, resourceType)
    local currentAmount

    if resourceType == "fluid" then
        currentAmount = AE2.getFluidAmount(name)
    else
        currentAmount = AE2.getItemAmount(name)
    end

    return currentAmount >= requiredAmount, currentAmount
end

-- Check all requirements for a tier
-- requirements: table of { name, amount, type }
-- Returns: allMet (boolean), results (table with details for each requirement)
function AE2.checkTierRequirements(requirements)
    if not requirements or #requirements == 0 then
        return false, {}
    end

    local allMet = true
    local results = {}

    for _, req in ipairs(requirements) do
        local hasEnough, currentAmount = AE2.checkRequirement(
            req.name,
            req.amount,
            req.type or "item"
        )

        table.insert(results, {
            name = req.name,
            required = req.amount,
            current = currentAmount,
            met = hasEnough,
            type = req.type or "item"
        })

        if not hasEnough then
            allMet = false
        end
    end

    return allMet, results
end

-- Get a formatted string for the amount (with commas/underscores)
function AE2.formatNumber(num)
    if type(num) ~= "number" then return tostring(num) end
    local str = tostring(math.floor(num))
    local parts = {}
    local len = #str
    local firstGroup = len % 3
    if firstGroup == 0 then firstGroup = 3 end
    table.insert(parts, str:sub(1, firstGroup))
    local i = firstGroup + 1
    while i <= len do
        table.insert(parts, str:sub(i, i + 2))
        i = i + 3
    end
    return table.concat(parts, ",")
end

-- List all fluids in network (for debugging)
function AE2.listFluids()
    if not ME then
        AE2.init()
    end

    local fluids = ME.getFluidsInNetwork()
    if not fluids then
        return {}
    end

    local list = {}
    for _, fluid in pairs(fluids) do
        table.insert(list, {
            name = fluid.label or "Unknown",
            amount = fluid.amount or 0
        })
    end

    return list
end

-- List all items in network (for debugging - be careful, can be large!)
function AE2.listItems(filter)
    if not ME then
        AE2.init()
    end

    local items
    if filter then
        items = ME.getItemsInNetwork({ label = filter })
    else
        items = ME.getItemsInNetwork()
    end

    if not items then
        return {}
    end

    local list = {}
    for _, item in pairs(items) do
        table.insert(list, {
            name = item.label or "Unknown",
            amount = item.size or 0
        })
    end

    return list
end

return AE2
