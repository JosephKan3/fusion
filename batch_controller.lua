-- Batch Redstone Output Controller
-- Monitors AE2 for recipe requests and only outputs redstone if all inputs are above threshold

local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local shell = require("shell")
local gpu = component.gpu
local filesystem = require("filesystem")

local ae2 = require("src.AE2")
local recipesConfig = require("recipes_config")
local redstoneConfig = require("redstone_config")

local REDSTONE_ON = 15
local REDSTONE_OFF = 0
local CHECK_INTERVAL = 10 -- seconds

-- Find ME Interface for checking crafting status
local meInterface = nil
local function findMEInterface()
    for address, name in component.list() do
        if string.find(name, "interface") then
            local proxy = component.proxy(address)
            if proxy.getCpus then
                return proxy
            end
        end
    end
    return nil
end

-- Helper: round up division
local function ceildiv(a, b)
    return math.floor((a + b - 1) / b)
end

-- Set redstone output for a specific tier
local function setRedstoneOutput(tier, value)
    local tierConfig = redstoneConfig.tiers[tier]
    if tierConfig and tierConfig.address then
        local redstone = component.proxy(tierConfig.address)
        if redstone then
            redstone.setOutput(tierConfig.side, value)
            return true
        else
            print(string.format("Warning: Could not proxy redstone at %s", tierConfig.address:sub(1, 8)))
            return false
        end
    else
        print(string.format("Warning: No redstone configured for tier %d", tier))
        return false
    end
end

-- Enable redstone signal for a tier
local function enableRedstone(tier)
    return setRedstoneOutput(tier, REDSTONE_ON)
end

-- Disable redstone signal for a tier
local function disableRedstone(tier)
    return setRedstoneOutput(tier, REDSTONE_OFF)
end

-- Helper to safely collect items from CPU lists
local function collectItems(source)
    local list = {}
    -- Try calling if it's a function or callable table
    if type(source) == "function" or (type(source) == "table" and getmetatable(source) and getmetatable(source).__call) then
        local ok, res = pcall(source)
        if ok and res then source = res end
    end

    if type(source) == "table" then
        for _, item in ipairs(source) do
            local display_name = item.label or item.name or "Unknown"
            table.insert(list, { name = display_name, size = item.size or 1 })
        end
    end
    return list
end

-- Check if an item is currently being crafted
local function isItemBeingCrafted(itemName)
    if not meInterface then
        return false
    end

    local success, cpus = pcall(meInterface.getCpus)
    if not success or not cpus then
        return false
    end

    for i, cpu_wrapper in ipairs(cpus) do
        local internal = cpu_wrapper.cpu
        if internal and cpu_wrapper.busy then
            -- Check finalOutput first
            if internal.finalOutput then
                local out = internal.finalOutput
                if type(out) == "function" then
                    local _, r = pcall(out)
                    out = r
                end

                if out and type(out) == "table" then
                    local name = out.label or out.name or "Unknown"
                    if name == itemName then
                        return true
                    end
                end
            end

            -- Check active items
            if internal.activeItems then
                local activeList = collectItems(internal.activeItems)
                for _, item in ipairs(activeList) do
                    if item.name == itemName then
                        return true
                    end
                end
            end

            -- Check pending items
            if internal.pendingItems then
                local pendingList = collectItems(internal.pendingItems)
                for _, item in ipairs(pendingList) do
                    if item.name == itemName then
                        return true
                    end
                end
            end

            -- Check stored items
            if internal.storedItems then
                local storedList = collectItems(internal.storedItems)
                for _, item in ipairs(storedList) do
                    if item.name == itemName then
                        return true
                    end
                end
            end
        end
    end

    return false
end

-- Main logic
local function checkAndOutputRedstone()
    for recipeName, recipe in pairs(recipesConfig.recipes) do
        local outputName = recipe.output.name
        local isCrafting = isItemBeingCrafted(outputName)

        if isCrafting then
            print(string.format("Detected active craft for: %s", outputName))

            -- Check if all inputs are present in the crafting system
            local allInputsSufficient = true
            for _, input in ipairs(recipe.inputs) do
                local stored = 0
                if input.type == "fluid" then
                    stored = ae2.getFluidAmount(input.name)
                else
                    stored = ae2.getItemAmount(input.name)
                end

                -- Check if the input is available (at least the recipe amount)
                if stored < input.amount then
                    allInputsSufficient = false
                    print(string.format("Insufficient %s: need %d, have %d", input.name, input.amount, stored))
                    break
                end
            end

            if allInputsSufficient then
                print(string.format("All inputs sufficient for %s. Outputting redstone signal!", outputName))
                if recipe.tier then
                    enableRedstone(recipe.tier)
                else
                    print(string.format("Warning: Recipe '%s' has no tier configured", recipeName))
                end
            else
                print(string.format("Not enough resources for %s. No redstone output.", outputName))
                if recipe.tier then
                    disableRedstone(recipe.tier)
                else
                    print(string.format("Warning: Recipe '%s' has no tier configured", recipeName))
                end
            end
        else
            -- No active craft detected, ensure redstone is off
            if recipe.tier then
                disableRedstone(recipe.tier)
            end
        end
    end
end

-- Initialize ME Interface
print("Batch Redstone Output Controller")
print("Initializing ME Interface...")
meInterface = findMEInterface()
if not meInterface then
    error("No ME Interface found! Cannot detect crafting requests.")
end
print("ME Interface found. Starting controller...")

-- Main loop
while true do
    checkAndOutputRedstone()
    os.sleep(CHECK_INTERVAL)
end
