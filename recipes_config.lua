-- Recipe configuration for batch redstone output controller
-- Defines recipes and thresholds for monitored crafts

local recipes = {
    ["Tritanium Ingot"] = {
        inputs = {
            { name = "Molten Duranium", amount = 288, type = "fluid" },
            { name = "Molten Titanium", amount = 432, type = "fluid" },
        },
        output = { name = "Tritanium Ingot", amount = 1, type = "item" },
        tier = 1, -- Redstone tier for this recipe
    },
    -- Add more recipes here as needed
}

-- Minimum batch size for output (absolute, not percent)
local ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE = 10
-- Default percent threshold for batch (e.g., 0.10 for 10%)
local DEFAULT_BATCH_PERCENT = 0.10

return {
    recipes = recipes,
    ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE = ABSOLUTE_MINIMUM_OUTPUT_RECIPE_BATCH_SIZE,
    DEFAULT_BATCH_PERCENT = DEFAULT_BATCH_PERCENT,
}


