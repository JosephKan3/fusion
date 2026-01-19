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

-- Get requested craft amount for a recipe (stub: replace with actual request logic)
local function getRequestedAmount(recipeName)
    -- TODO: Replace with actual logic to read requested amount from AE2 or user input
    return 90 -- Example: 90 tritanium requested
end

-- Main logic
local function checkAndOutputRedstone()
    for recipeName, recipe in pairs(recipesConfig.recipes) do
        local requested = getRequestedAmount(recipeName)
        if requested and requested > 0 then
            local batchPercent = recipesConfig.DEFAULT_BATCH_PERCENT
            local minBatch = recipesConfig.ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE
            local batchSize = math.max(ceildiv(requested * batchPercent, 1), minBatch)

            local allInputsSufficient = true
            for _, input in ipairs(recipe.inputs) do
                local stored = 0
                if input.type == "fluid" then
                    stored = ae2.getFluidAmount(input.name)
                else
                    stored = ae2.getItemAmount(input.name)
                end
                if stored < batchSize * input.amount then
                    allInputsSufficient = false
                    print(string.format("Insufficient %s: need %d, have %d", input.name, batchSize * input.amount, stored))
                    break
                end
            end

            if allInputsSufficient then
                print(string.format("All inputs sufficient for %s batch. Outputting redstone signal!", recipeName))
                if recipe.tier then
                    enableRedstone(recipe.tier)
                else
                    print(string.format("Warning: Recipe '%s' has no tier configured", recipeName))
                end
            else
                print(string.format("Not enough resources for %s batch. No redstone output.", recipeName))
                if recipe.tier then
                    disableRedstone(recipe.tier)
                else
                    print(string.format("Warning: Recipe '%s' has no tier configured", recipeName))
                end
            end
        end
    end
end

-- Main loop
while true do
    checkAndOutputRedstone()
    os.sleep(CHECK_INTERVAL)
end
