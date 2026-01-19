-- Waterline Tier Controller
-- Monitors AE2 network and activates tier-based redstone controls
-- Control 0 activates with the highest active tier (1-8)
-- Usage: controller [debug]

local component = require("component")
local computer = require("computer")
local event = require("event")
local term = require("term")
local shell = require("shell")
local gpu = component.gpu
local filesystem = require("filesystem")

-- Parse arguments
local args = {...}
local DEBUG_MODE = args[1] == "debug"

-- Load configurations
local tiersConfigModule = require("tiers_config")
local tiersConfig = tiersConfigModule.requirements
local minimumsConfig = tiersConfigModule.minimums
local redstoneConfig = require("redstone_config")
local ae2 = require("src.AE2")

-- Constants
local REDSTONE_ON = 15
local REDSTONE_OFF = 0
local CHECK_INTERVAL = DEBUG_MODE and 5 or (redstoneConfig.check_interval or 120)
local PULSE_DURATION = 1 -- seconds

-- State tracking
local tierStates = {} -- Current on/off state for each tier
local redstoneProxies = {} -- Cached redstone component proxies

-- Colors for display
local COLOR_GREEN = 0x00FF00
local COLOR_RED = 0xFF0000
local COLOR_YELLOW = 0xFFFF00
local COLOR_GRAY = 0x808080
local COLOR_WHITE = 0xFFFFFF
local COLOR_MAGENTA = 0xFF00FF

-- Initialize AE2 module
local function initAE2()
    local success, err = pcall(function()
        ae2.init(redstoneConfig.me_interface)
    end)
    if not success then
        print("ERROR: " .. tostring(err))
        return false
    end
    return true
end

-- Get or create redstone component proxy
local function getRedstoneProxy(address)
    if not address then return nil end

    if redstoneProxies[address] then
        return redstoneProxies[address]
    end

    local success, proxy = pcall(component.proxy, address)
    if success and proxy then
        redstoneProxies[address] = proxy
        return proxy
    end

    return nil
end

-- Set redstone output for a tier
local function setRedstoneOutput(tierNum, value)
    local tierConfig = redstoneConfig.tiers[tierNum]
    if not tierConfig then return false end

    local proxy = getRedstoneProxy(tierConfig.address)
    if not proxy then
        print(string.format("Warning: Could not access redstone for tier %d", tierNum))
        return false
    end

    local success, err = pcall(function()
        proxy.setOutput(tierConfig.side, value)
    end)

    if not success then
        print(string.format("Error setting redstone for tier %d: %s", tierNum, tostring(err)))
        return false
    end

    return true
end

-- Get real time from filesystem
local function getRealTime()
    local tempfile = "/tmp/waterline_timefile"
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

-- Check a single tier's requirements
local function checkTier(tierNum)
    local requirements = tiersConfig[tierNum]
    if not requirements or #requirements == 0 then
        return false, nil
    end

    local allMet, results = ae2.checkTierRequirements(requirements)
    return allMet, results
end

-- Check a tier's output fluid level against its minimum threshold
-- Returns: isBelowMinimum (boolean), currentAmount (number), minimumAmount (number)
local function checkTierMinimum(tierNum)
    local minConfig = minimumsConfig[tierNum]
    if not minConfig or not minConfig.amount or minConfig.amount <= 0 then
        return false, 0, 0
    end

    local currentAmount = ae2.getFluidAmount(minConfig.name)
    local isBelowMinimum = currentAmount < minConfig.amount
    return isBelowMinimum, currentAmount, minConfig.amount
end

-- Find all tiers that are below their minimum thresholds
-- Returns: table of tier numbers that are below minimum (sorted ascending)
local function findTiersBelowMinimum()
    local belowMinimum = {}
    for tierNum = 1, 8 do
        local isBelowMin, _, _ = checkTierMinimum(tierNum)
        if isBelowMin then
            table.insert(belowMinimum, tierNum)
        end
    end
    return belowMinimum
end

-- Main check and update cycle
local function updateTiers()
    local selectedTier = 0
    local tierResults = {}
    local minimumStatus = {} -- Track minimum status for display

    -- Check each tier (1-8) to find which are ready and their minimum status
    local readyTiers = {}
    for tierNum = 1, 8 do
        local met, results = checkTier(tierNum)
        tierResults[tierNum] = {
            met = met,
            results = results
        }

        if met then
            readyTiers[tierNum] = true
            tierStates[tierNum] = true
        else
            tierStates[tierNum] = false
        end

        -- Check minimum status for this tier
        local isBelowMin, currentAmt, minAmt = checkTierMinimum(tierNum)
        minimumStatus[tierNum] = {
            belowMinimum = isBelowMin,
            current = currentAmt,
            minimum = minAmt,
            name = minimumsConfig[tierNum] and minimumsConfig[tierNum].name or nil
        }
    end

    -- Find tiers below minimum (sorted from lowest to highest)
    local tiersBelowMin = findTiersBelowMinimum()

    -- Priority logic:
    -- 1. Check tiers below minimum, starting from lowest tier
    -- 2. If a tier below minimum is ready (has prerequisites), run it
    -- 3. If no tier below minimum can run, fall back to highest ready tier
    local priorityTier = nil
    for _, tierNum in ipairs(tiersBelowMin) do
        if readyTiers[tierNum] then
            priorityTier = tierNum
            break -- Found the lowest tier below minimum that can run
        end
    end

    if priorityTier then
        selectedTier = priorityTier
    else
        -- Fall back to normal behavior: run highest ready tier
        for tierNum = 1, 8 do
            if readyTiers[tierNum] then
                selectedTier = tierNum
            end
        end
    end

    -- Update control 0 state
    tierStates[0] = selectedTier > 0

    -- Pulse redstone: only activate selected tier + tier 0
    if selectedTier > 0 then
        local tierConfig = redstoneConfig.tiers[selectedTier]
        local control0Config = redstoneConfig.tiers[0]

        -- Beep to indicate cycle trigger
        computer.beep(1000, 0.2)

        -- Turn ON selected tier and tier 0
        if tierConfig then
            setRedstoneOutput(selectedTier, REDSTONE_ON)
        end
        if control0Config then
            setRedstoneOutput(0, REDSTONE_ON)
        end

        -- Wait for pulse duration
        os.sleep(PULSE_DURATION)

        -- Turn OFF
        if tierConfig then
            setRedstoneOutput(selectedTier, REDSTONE_OFF)
        end
        if control0Config then
            setRedstoneOutput(0, REDSTONE_OFF)
        end
    end

    return selectedTier, tierResults, minimumStatus
end

-- Display status
local function displayStatus(selectedTier, tierResults, minimumStatus)
    term.clear()
    term.setCursor(1, 1)

    local title = "=== Waterline Tier Controller ==="
    if DEBUG_MODE then
        title = "=== Waterline Tier Controller [DEBUG] ==="
    end
    printColored(title, COLOR_WHITE)
    print(string.format("Check Interval: %d seconds | Press Q to exit", CHECK_INTERVAL))
    print("")

    -- Control 0 status
    local ctrl0Status = tierStates[0] and "RUNNING" or "OFF"
    local ctrl0Color = tierStates[0] and COLOR_MAGENTA or COLOR_GRAY
    log(string.format("MAIN CONTROLLER: %s", ctrl0Status), ctrl0Color)
    print("")

    -- Display each tier
    for tierNum = 1, 8 do
        local tierConfig = redstoneConfig.tiers[tierNum]
        local result = tierResults[tierNum]
        local minStatus = minimumStatus and minimumStatus[tierNum]

        if not tierConfig then
            log(string.format("Tier %d: Not configured", tierNum), COLOR_GRAY)
        elseif not result or not result.results then
            log(string.format("Tier %d: No requirements defined", tierNum), COLOR_GRAY)
        else
            local statusText
            local statusColor

            if tierNum == selectedTier then
                -- This is the running tier
                statusText = "RUNNING"
                statusColor = COLOR_MAGENTA
            elseif result.met then
                -- Has inputs but not the selected tier
                statusText = "WAITING"
                statusColor = COLOR_GREEN
            else
                -- Missing inputs
                statusText = "UNAVAILABLE"
                statusColor = COLOR_GRAY
            end

            -- Build minimum indicator if configured
            local minIndicator = ""
            if minStatus and minStatus.minimum > 0 then
                local currentStr = ae2.formatNumber(minStatus.current)
                local minStr = ae2.formatNumber(minStatus.minimum)
                if minStatus.belowMinimum then
                    minIndicator = string.format(" [LOW %s/%s]", currentStr, minStr)
                else
                    minIndicator = string.format(" [%s/%s]", currentStr, minStr)
                end
            end

            -- Print tier line with colored minimum indicator
            local old = gpu.getForeground()
            io.write("[" .. getFormattedTime() .. "] ")
            gpu.setForeground(statusColor)
            io.write(string.format("Tier %d: %s", tierNum, statusText))
            if minIndicator ~= "" then
                if minStatus.belowMinimum then
                    gpu.setForeground(COLOR_YELLOW)
                else
                    gpu.setForeground(COLOR_GREEN)
                end
                io.write(minIndicator)
            end
            gpu.setForeground(old)
            print("")

            -- Show individual requirements
            for _, req in ipairs(result.results) do
                local reqColor = req.met and COLOR_GREEN or COLOR_RED
                local currentStr = ae2.formatNumber(req.current)
                local requiredStr = ae2.formatNumber(req.required)
                local icon = req.met and "[OK]" or "[!!]"

                old = gpu.getForeground()
                io.write("         ")
                gpu.setForeground(reqColor)
                io.write(icon .. " ")
                gpu.setForeground(COLOR_WHITE)
                print(string.format("%s: %s / %s (%s)",
                    req.name, currentStr, requiredStr, req.type))
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

-- Main loop
local function main()
    term.clear()
    term.setCursor(1, 1)

    print("=== Waterline Tier Controller ===")
    print("Initializing...")

    -- Initialize AE2
    if not initAE2() then
        print("Failed to initialize AE2 module. Exiting.")
        return
    end
    print("AE2 connection established.")

    -- Validate redstone config
    local configuredTiers = 0
    for tierNum = 0, 8 do
        if redstoneConfig.tiers[tierNum] then
            configuredTiers = configuredTiers + 1
        end
    end
    print(string.format("Configured tiers: %d", configuredTiers))

    if configuredTiers == 0 then
        print("WARNING: No tiers configured! Run setup.lua first.")
    end

    os.sleep(2)

    -- Main loop
    while true do
        local selectedTier, results, minStatus
        local success, err = pcall(function()
            selectedTier, results, minStatus = updateTiers()
            displayStatus(selectedTier, results, minStatus)
        end)

        if not success then
            log("Error during update: " .. tostring(err), COLOR_RED)
        end

        -- Countdown loop using real time
        local endTime = computer.uptime() + CHECK_INTERVAL
        while true do
            local remaining = math.ceil(endTime - computer.uptime())
            if remaining <= 0 then break end

            displayCountdown(remaining)

            -- Sleep for 1 second using OS sleep
            os.sleep(1)

            -- Check for key press (non-blocking)
            local eventType, _, _, code = event.pull(0, "key_down")
            if eventType == "key_down" and code == 0x10 then -- Q key
                shutdown()
                term.clear()
                term.setCursor(1, 1)
                print("Waterline Tier Controller stopped.")
                return
            end
        end
    end
end

-- Run with error handling
local success, err = pcall(main)
if not success then
    print("Fatal error: " .. tostring(err))
    shutdown()
end
