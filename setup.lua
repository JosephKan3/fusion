-- Waterline Tier Controller Setup
-- Downloads files from GitHub and configures redstone I/O blocks

local fs = require("filesystem")
local shell = require("shell")
local internet = require("internet")
local json = require("json")
local component = require("component")
local term = require("term")

local args = {...}
local branch = args[1] or "main"
local repo = args[2] or "JosephKan3/fusion"

local CONFIG_FILE = "recipes_config.lua"

-- ============================================
-- GitHub Download Functions
-- ============================================

local function getFileList(repository, branchName)
    local url = string.format("https://api.github.com/repos/%s/contents/?ref=%s", repository, branchName)
    local handle = internet.request(url)
    if not handle then
        error("HTTP request failed")
    end

    local data = ""
    for chunk in handle do data = data .. chunk end
    return json.decode(data)
end

local function downloadFiles()
    print("\n=== Downloading Fusion Files ===")

    -- Preserve existing configs
    local preserveRecipesConfig = fs.exists(CONFIG_FILE)
    if preserveRecipesConfig then
        print("Preserving existing " .. CONFIG_FILE)
        shell.execute("cp " .. CONFIG_FILE .. " " .. CONFIG_FILE .. ".bak")
    end


    -- Create directories
    dirs = { "src" }
    for _, dir in ipairs(dirs) do
        local path = shell.getWorkingDirectory() .. "/" .. dir
        if not fs.exists(path) then
            fs.makeDirectory(path)
        end
    end

    print("Fetching file list from repository...")
    local files = getFileList(repo, branch)

    -- Download root lua files
    for _, file in ipairs(files) do
        if file.type == "file" and file.name:match("%.lua$") then
            -- Skip config file if it exists
            if (file.name == CONFIG_FILE and preserveRecipesConfig) then
                print("Skipping " .. file.name .. " (preserving local copy)")
            else
                print("Downloading " .. file.name)
                shell.execute(string.format(
                    "wget -f https://raw.githubusercontent.com/%s/%s/%s",
                    repo, branch, file.path
                ))
            end
        end
    end

    -- Restore config if preserved
    if preserveRecipesConfig then
        shell.execute("mv " .. CONFIG_FILE .. ".bak " .. CONFIG_FILE)
    end

    print("Downloading src/AE2.lua")
    shell.execute(string.format(
        "wget -f https://raw.githubusercontent.com/%s/%s/src/AE2.lua src/AE2.lua",
        repo, branch
    ))

    print("\nFiles downloaded successfully!")
end

-- ============================================
-- Configuration Functions
-- ============================================

local function clearScreen()
    term.clear()
    term.setCursor(1, 1)
end

local function printHeader()
    print("===========================================")
    print("   Fusion Batch Controller Setup")
    print("===========================================")
    print("")
end

local function listRedstoneComponents()
    print("Available Redstone I/O components:")
    print("-----------------------------------")
    local count = 0
    for address, componentType in component.list("redstone") do
        count = count + 1
        print(string.format("  [%d] %s", count, address))
    end
    if count == 0 then
        print("  (No redstone components found)")
    end
    print("")
    return count
end

local function getRedstoneAddresses()
    local addresses = {}
    for address, _ in component.list("redstone") do
        table.insert(addresses, address)
    end
    return addresses
end

local function getSideNumber(sideName)
    local sides = {
        bottom = 0, down = 0,
        top = 1, up = 1,
        back = 2, north = 2,
        front = 3, south = 3,
        right = 4, west = 4,
        left = 5, east = 5
    }
    return sides[sideName:lower()]
end

local function getSideName(sideNum)
    local names = {
        [0] = "bottom",
        [1] = "top",
        [2] = "north",
        [3] = "south",
        [4] = "west",
        [5] = "east"
    }
    return names[sideNum] or "unknown"
end

local function promptForTier(tierNum, addresses)
    print(string.format("\n--- Controller %d Configuration ---", tierNum))

    -- Prompt for address
    io.write("Enter redstone I/O address (or number from list, or 'skip'): ")
    local input = io.read()

    if input:lower() == "skip" or input == "" then
        return nil
    end

    local address
    local num = tonumber(input)
    if num and num >= 1 and num <= #addresses then
        address = addresses[num]
    else
        -- Validate address format (partial or full)
        address = input
        -- Check if it's a valid component
        local found = false
        for addr, _ in component.list("redstone") do
            if addr:find(input, 1, true) or addr == input then
                address = addr
                found = true
                break
            end
        end
        if not found then
            print("Warning: Could not verify address. Using as-is.")
        end
    end

    -- Prompt for side
    print("Sides: bottom(0), top(1), north(2), south(3), west(4), east(5)")
    io.write("Enter output side (name or number): ")
    local sideInput = io.read()

    local side
    local sideNum = tonumber(sideInput)
    if sideNum and sideNum >= 0 and sideNum <= 5 then
        side = sideNum
    else
        side = getSideNumber(sideInput)
        if not side then
            print("Invalid side. Defaulting to 'south' (3).")
            side = 3
        end
    end

    return {
        address = address,
        side = side
    }
end

local function promptForMEInterface()
    print("\n--- ME Interface Configuration ---")
    print("Available ME Interface components:")
    local count = 0
    for address, _ in component.list("me_interface") do
        count = count + 1
        print(string.format("  [%d] %s", count, address))
    end

    if count == 0 then
        print("  (No ME Interface found - will use first available)")
        return nil
    end

    io.write("Enter ME Interface address (or number, or Enter for auto): ")
    local input = io.read()

    if input == "" then
        return nil -- Auto-detect
    end

    local num = tonumber(input)
    if num then
        local addresses = {}
        for addr, _ in component.list("me_interface") do
            table.insert(addresses, addr)
        end
        if num >= 1 and num <= #addresses then
            return addresses[num]
        end
    end

    return input
end

local function saveConfig(config)
    local file = io.open(CONFIG_FILE, "w")
    if not file then
        print("ERROR: Could not write " .. CONFIG_FILE)
        return false
    end

    file:write("-- Waterline Redstone Configuration\n")
    file:write("-- Generated by setup.lua\n\n")
    file:write("local config = {}\n\n")

    -- ME Interface
    if config.me_interface then
        file:write(string.format("config.me_interface = %q\n\n", config.me_interface))
    else
        file:write("config.me_interface = nil -- Auto-detect\n\n")
    end

    -- Check interval
    file:write(string.format("config.check_interval = %d -- seconds\n\n", config.check_interval or 120))

    -- Tier configurations
    file:write("-- Tier redstone outputs\n")
    file:write("-- Format: { address = \"...\", side = N }\n")
    file:write("-- Sides: bottom=0, top=1, north=2, south=3, west=4, east=5\n")
    file:write("config.tiers = {\n")

    for i = 0, 8 do
        local tier = config.tiers[i]
        if tier then
            file:write(string.format("    [%d] = { address = %q, side = %d }, -- %s\n",
                i, tier.address, tier.side, getSideName(tier.side)))
        else
            file:write(string.format("    [%d] = nil,\n", i))
        end
    end

    file:write("}\n\n")
    file:write("return config\n")
    file:close()

    print("\nConfiguration saved to " .. CONFIG_FILE)
    return true
end

local function loadExistingConfig()
    if not fs.exists(CONFIG_FILE) then
        return nil
    end

    local success, config = pcall(dofile, CONFIG_FILE)
    if success then
        return config
    end
    return nil
end

local function setupHardware()
    clearScreen()
    printHeader()

    -- Check for existing config
    local existingConfig = loadExistingConfig()
    if existingConfig then
        io.write("Existing configuration found. Reconfigure? (y/n): ")
        local response = io.read()
        if response:lower() ~= "y" then
            print("Hardware setup cancelled.")
            return
        end
    end

    clearScreen()
    printHeader()

    local addresses = getRedstoneAddresses()
    listRedstoneComponents()

    local config = {
        tiers = {},
        check_interval = 5
    }

    -- Configure ME Interface
    config.me_interface = promptForMEInterface()

    -- Configure check interval
    print("\n--- Check Interval ---")
    io.write("Enter check interval in seconds (default 5): ")
    local intervalInput = io.read()
    local interval = tonumber(intervalInput)
    if interval and interval > 0 then
        config.check_interval = interval
    end

    -- Configure each tier
    print("\n=== Controller Configuration ===")
    print("Configure each redstone output (1-8)")
    print("Controllers 1-8 control individual machines")
    print("")

    for i = 1, 8 do
        config.tiers[i] = promptForTier(i, addresses)
    end

    -- Summary
    clearScreen()
    printHeader()
    print("Configuration Summary:")
    print("-----------------------")

    if config.me_interface then
        print("ME Interface: " .. config.me_interface)
    else
        print("ME Interface: Auto-detect")
    end
    print("Check Interval: " .. config.check_interval .. " seconds")
    print("")

    for i = 0, 8 do
        local tier = config.tiers[i]
        if tier then
            print(string.format("Tier %d: %s (side: %s)",
                i, tier.address:sub(1, 8) .. "...", getSideName(tier.side)))
        else
            print(string.format("Tier %d: Not configured", i))
        end
    end

    print("")
    io.write("Save this configuration? (y/n): ")
    local confirm = io.read()

    if confirm:lower() == "y" then
        saveConfig(config)
        print("\nHardware setup complete!")
    else
        print("Configuration not saved.")
    end
end

-- ============================================
-- Main
-- ============================================

local function main()
    clearScreen()
    printHeader()

    -- Download files from GitHub
    downloadFiles()

    -- Setup hardware
    print("")
    io.write("Configure hardware now? (y/n): ")
    local response = io.read()

    if response:lower() == "y" then
        setupHardware()
    else
        print("\nRun 'setup' again to configure hardware later.")
    end

    print("\n=== Setup Complete ===")
    print("1. Edit 'tiers_config.lua' to set material requirements for each tier")
    print("2. Run 'controller' to start the tier controller")
end

main()
