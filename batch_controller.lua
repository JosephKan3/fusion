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

-- Colors for display
local COLOR_GREEN = 0x00FF00
local COLOR_RED = 0xFF0000
local COLOR_YELLOW = 0xFFFF00
local COLOR_GRAY = 0x808080
local COLOR_WHITE = 0xFFFFFF
local COLOR_MAGENTA = 0xFF00FF

-- Get real time from filesystem
local function getRealTime()
    local tempfile = "/tmp/batch_controller_timefile"
    local file = filesystem.open(tempfile, "a")
    if file then
        file:close()
        local timestamp = filesystem.lastModified(tempfile) / 1000
        filesystem.remove(tempfile)
        return timestamp
    else
        return os.time()
    end
end

-- Format time for display
local function getFormattedTime()
    local timestamp = getRealTime()
    local timetable = os.date("*t", timestamp)

    local hour = timetable.hour
    local min = timetable.min
    local sec = timetable.sec

    if min < 10 then min = "0" .. min end
    if sec < 10 then sec = "0" .. sec end

    return hour .. ":" .. min .. ":" .. sec
end

-- Print with color
local function printColored(text, color)
    local old = gpu.getForeground()
    if color then gpu.setForeground(color) end
    print(text)
    gpu.setForeground(old)
end

-- Print timestamped log
local function log(text, color)
    local old = gpu.getForeground()
    io.write("[" .. getFormattedTime() .. "] ")
    if color then gpu.setForeground(color) end
    print(text)
    gpu.setForeground(old)
end

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

-- Main logic - returns status for each recipe
local function checkAndOutputRedstone()
    local recipeStatuses = {}

    for recipeName, recipe in pairs(recipesConfig.recipes) do
        local outputName = recipe.output.name
        local isCrafting = isItemBeingCrafted(outputName)

        local status = {
            name = recipeName,
            outputName = outputName,
            tier = recipe.tier,
            crafting = isCrafting,
            redstoneActive = false,
            inputsStatus = {}
        }

        if isCrafting then
            -- Check if all inputs are present in the crafting system
            local allInputsSufficient = true
            for _, input in ipairs(recipe.inputs) do
                local stored = 0
                if input.type == "fluid" then
                    stored = ae2.getFluidAmount(input.name)
                else
                    stored = ae2.getItemAmount(input.name)
                end

                local inputStatus = {
                    name = input.name,
                    type = input.type,
                    required = input.amount,
                    current = stored,
                    met = stored >= input.amount
                }
                table.insert(status.inputsStatus, inputStatus)

                if stored < input.amount then
                    allInputsSufficient = false
                end
            end

            if allInputsSufficient then
                if recipe.tier then
                    enableRedstone(recipe.tier)
                    status.redstoneActive = true
                end
            else
                if recipe.tier then
                    disableRedstone(recipe.tier)
                end
            end
        else
            -- No active craft detected, ensure redstone is off
            if recipe.tier then
                disableRedstone(recipe.tier)
            end
        end

        table.insert(recipeStatuses, status)
    end

    return recipeStatuses
end

-- Display status
local function displayStatus(recipeStatuses)
    term.clear()
    term.setCursor(1, 1)

    printColored("=== Batch Redstone Output Controller ===", COLOR_WHITE)
    print(string.format("Check Interval: %d seconds | Press Q to exit", CHECK_INTERVAL))
    print("")

    -- Display each recipe
    for _, status in ipairs(recipeStatuses) do
        if not status.tier then
            log(string.format("%s: Not configured (no tier)", status.name), COLOR_GRAY)
        elseif not status.crafting then
            log(string.format("%s: No active craft", status.name), COLOR_GRAY)
        else
            -- Recipe is being crafted
            local statusText
            local statusColor

            if status.redstoneActive then
                statusText = "RUNNING (Redstone ON)"
                statusColor = COLOR_MAGENTA
            else
                statusText = "WAITING (Insufficient Inputs)"
                statusColor = COLOR_YELLOW
            end

            log(string.format("%s: %s", status.outputName, statusText), statusColor)

            -- Show individual input requirements
            for _, input in ipairs(status.inputsStatus) do
                local reqColor = input.met and COLOR_GREEN or COLOR_RED
                local currentStr = ae2.formatNumber(input.current)
                local requiredStr = ae2.formatNumber(input.required)
                local icon = input.met and "[OK]" or "[!!]"

                local old = gpu.getForeground()
                io.write("         ")
                gpu.setForeground(reqColor)
                io.write(icon .. " ")
                gpu.setForeground(COLOR_WHITE)
                print(string.format("%s: %s / %s (%s)",
                    input.name, currentStr, requiredStr, input.type))
                gpu.setForeground(old)
            end
        end
    end

    print("")
end

-- Display countdown on a single line (updates in place)
local function displayCountdown(seconds)
    local _, height = gpu.getResolution()
    term.setCursor(1, height)
    gpu.setForeground(COLOR_GRAY)
    term.clearLine()
    io.write(string.format("[%s] Next check in %d seconds... (Press Q to exit)", getFormattedTime(), seconds))
    gpu.setForeground(COLOR_WHITE)
end

-- Shutdown - turn off all redstone outputs
local function shutdown()
    print("\nShutting down...")
    for tierNum = 0, 8 do
        local tierConfig = redstoneConfig.tiers[tierNum]
        if tierConfig then
            setRedstoneOutput(tierNum, REDSTONE_OFF)
        end
    end
    print("All redstone outputs disabled.")
end

-- Main function
local function main()
    term.clear()
    term.setCursor(1, 1)

    printColored("=== Batch Redstone Output Controller ===", COLOR_WHITE)
    print("Initializing...")

    -- Initialize ME Interface
    meInterface = findMEInterface()
    if not meInterface then
        printColored("ERROR: No ME Interface found! Cannot detect crafting requests.", COLOR_RED)
        return
    end
    printColored("ME Interface found.", COLOR_GREEN)

    -- Validate redstone config
    local configuredTiers = 0
    for tierNum = 0, 8 do
        if redstoneConfig.tiers[tierNum] then
            configuredTiers = configuredTiers + 1
        end
    end
    print(string.format("Configured tiers: %d", configuredTiers))

    if configuredTiers == 0 then
        printColored("WARNING: No tiers configured! Run setup.lua first.", COLOR_YELLOW)
    end

    os.sleep(2)

    -- Main loop
    while true do
        local statuses
        local success, err = pcall(function()
            statuses = checkAndOutputRedstone()
            displayStatus(statuses)
        end)

        if not success then
            log("Error during update: " .. tostring(err), COLOR_RED)
        end

        -- Countdown loop
        local endTime = computer.uptime() + CHECK_INTERVAL
        while true do
            local remaining = math.ceil(endTime - computer.uptime())
            if remaining <= 0 then break end

            displayCountdown(remaining)

            -- Sleep for 1 second
            os.sleep(1)

            -- Check for key press (non-blocking)
            local eventType, _, _, code = event.pull(0, "key_down")
            if eventType == "key_down" and code == 0x10 then -- Q key
                shutdown()
                term.clear()
                term.setCursor(1, 1)
                printColored("Batch Redstone Output Controller stopped.", COLOR_WHITE)
                return
            end
        end
    end
end

-- Run with error handling
local success, err = pcall(main)
if not success then
    printColored("Fatal error: " .. tostring(err), COLOR_RED)
    shutdown()
end
