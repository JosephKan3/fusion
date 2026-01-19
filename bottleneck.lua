local component = require("component")
local event = require("event")
local term = require("term")
local computer = require("computer")

-- Configuration
local config = {
  pollInterval = 2,
  interfacePattern = "interface",
  serverUrl = "https://184fb62aa50d.ngrok-free.app/api/updatew"
}

-- AE2 Helper Functions (Inlined)
local ae2 = {}

function ae2.findInterface(pattern)
  for address, name in component.list() do
    if string.find(name, pattern) then
      local proxy = component.proxy(address)
      if proxy.getCpus then return proxy end
    end
  end
  return nil
end

function ae2.getCPUBottlenecks(interfaceProxy)
  local cpu_status_list = {}
  local success, cpus = pcall(interfaceProxy.getCpus)
  if not success or not cpus then return {} end

  for i, cpu_wrapper in ipairs(cpus) do
    local internal = cpu_wrapper.cpu
    if internal then
      local status = {
        index = i,
        busy = cpu_wrapper.busy,
        active = {},
        pending = {},
        stored = {},
        finalOutput = nil
      }
      
      -- Helper to collect items safely from methods or tables
      local function collect(source)
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

      -- Collect from all lists
      if internal.activeItems then status.active = collect(internal.activeItems) end
      if internal.pendingItems then status.pending = collect(internal.pendingItems) end
      if internal.storedItems then status.stored = collect(internal.storedItems) end
      
      -- If any list has items, consider it busy
      if #status.active > 0 or #status.pending > 0 or #status.stored > 0 then
         status.busy = true
      end

      -- Check Final Output
      if internal.finalOutput then
         local out = internal.finalOutput
         if type(out) == "function" then local _, r = pcall(out) out = r end
         
         if out and type(out) == "table" then
             local name = out.label or out.name or "Unknown"
             status.finalOutput = name
         end
      end
      
      table.insert(cpu_status_list, status)
    end
  end
  return cpu_status_list
end

-- Main Program Logic
local running = true
local tracker = {} -- [cpu_index] = { start_time = 123.4, signature = "item_name" }

local function formatTime(seconds)
  local int_seconds = math.floor(seconds)
  if int_seconds < 60 then
    return string.format("%ds", int_seconds)
  else
    local web = math.floor(int_seconds / 60)
    local s = int_seconds % 60
    return string.format("%dm %ds", web, s)
  end
end

local function main()
  term.clear()
  print("AE2 Bottleneck Finder (Single File)")
  print("Initializing...")

  local interface = ae2.findInterface(config.interfacePattern)
  if not interface then
    error("No ME Interface found matching: " .. config.interfacePattern)
  end
  
  if not interface then
    error("No ME Interface found matching: " .. config.interfacePattern)
  end
  
  while running do
    local function cycle()
        local cpus = ae2.getCPUBottlenecks(interface)
        local current_time = computer.uptime()
        local seen_cpus = {}

        term.clear()
        term.setCursor(1, 1)
        print("Active Jobs & Bottlenecks (Ctrl+C to stop)")
        print(string.format("Time: %s", os.date("%H:%M:%S")))
        print("------------------------------------------")
        
        local busy_cpus = {}
        
        -- 1. Identify and update trackers for all busy CPUs
        for _, cpu in ipairs(cpus) do
            if cpu.busy then
                seen_cpus[cpu.index] = true
                
                -- Initialize tracker for this CPU if missing (New Job Started)
                if not tracker[cpu.index] then
                    tracker[cpu.index] = { start_time = current_time, signature = "init", items = {} }
                end
                local cpu_tracker = tracker[cpu.index]

                -- Determine active job signature (Active 1 or Pending 1 or FinalOutput)
                -- We prefer active items as they represent what's actually happening
                local sig = nil
                if cpu.finalOutput and cpu.finalOutput ~= "finalOutput" then sig = cpu.finalOutput end
                if (not sig) and #cpu.active > 0 then sig = cpu.active[1].name end
                if (not sig) and #cpu.pending > 0 then sig = cpu.pending[1].name end
                sig = sig or "Unknown Job"

                -- Update signature, but DO NOT RESET start_time just because label changed.
                -- This solves flickering when sub-crafts change.
                cpu_tracker.signature = sig
                
                cpu.duration = current_time - cpu_tracker.start_time
                cpu.display_label = sig

                -- Track Item Timers
                local current_items_seen = {}
                
                local function update_list_timers(list)
                    for _, item in ipairs(list) do
                        local name = item.name
                        if not cpu_tracker.items[name] then
                            cpu_tracker.items[name] = current_time
                        end
                        item.duration = current_time - cpu_tracker.items[name]
                        current_items_seen[name] = true
                    end
                    -- Sort list by duration descending
                    table.sort(list, function(a, b) return a.duration > b.duration end)
                end

                update_list_timers(cpu.active)
                update_list_timers(cpu.pending)
                update_list_timers(cpu.stored)

                -- Cleanup items not seen in this cycle
                for name, _ in pairs(cpu_tracker.items) do
                    if not current_items_seen[name] then
                        cpu_tracker.items[name] = nil
                    end
                end

                table.insert(busy_cpus, cpu)
            end
        end
        
        -- 2. Sort busy CPUs by duration (descending)
        table.sort(busy_cpus, function(a, b)
            return a.duration > b.duration
        end)
        
        -- 3. Print sorted list
        if #busy_cpus == 0 then
            print("No active jobs.")
            tracker = {}
        else
            for _, cpu in ipairs(busy_cpus) do
                print(string.format("CPU #%d - %s [%s]", cpu.index, cpu.display_label, formatTime(cpu.duration)))
                
                local function print_items(list, label)
                    if #list > 0 then
                        print("  " .. label .. ":")
                        for i, item in ipairs(list) do
                            print(string.format("    %d x %s [%s]", item.size, item.name, formatTime(item.duration)))
                            if i >= 10 then print("    ... (" .. (#list - 10) .. " more)") break end
                        end
                    end
                end
                
                print_items(cpu.active, "Active")
                print_items(cpu.pending, "Pending")
                print_items(cpu.stored, "Stored")
                print("-")
            end
            
            -- Cleanup old CPU trackers
            for idx, _ in pairs(tracker) do
                if not seen_cpus[idx] then tracker[idx] = nil end
            end
        end

        -- 4. Send Data to Web Server
        if config.serverUrl and #config.serverUrl > 0 then
            local internet = require("component").internet
            if internet then
                -- Simple JSON serializer for the payload
                local function serialize(val)
                    local t = type(val)
                    if t == "number" or t == "boolean" then return tostring(val)
                    elseif t == "string" then return string.format("%q", val)
                    elseif t == "table" then
                        local has_keys = false
                        for k,v in pairs(val) do 
                            if type(k) == "string" then has_keys = true break end 
                        end
                        local parts = {}
                        if has_keys then
                            for k,v in pairs(val) do
                                table.insert(parts, string.format("%q:%s", k, serialize(v)))
                            end
                            return "{" .. table.concat(parts, ",") .. "}"
                        else
                            for _,v in ipairs(val) do
                                table.insert(parts, serialize(v))
                            end
                            return "[" .. table.concat(parts, ",") .. "]"
                        end
                    end
                    return "null"
                end
                
                -- Construct payload manually to avoid circular refs in full CPU objects
                local payload_data = { cpus = {} }
                for _, cpu in ipairs(busy_cpus) do
                    local clean_cpu = {
                        index = cpu.index,
                        label = cpu.display_label,
                        duration = cpu.duration,
                        active = cpu.active,
                        pending = cpu.pending,
                        stored = cpu.stored
                    }
                    table.insert(payload_data.cpus, clean_cpu)
                end
                
                local json_str = serialize(payload_data)
                
                -- Send POST with explicit headers and method
                print("Sending " .. #json_str .. " bytes to " .. config.serverUrl)
                local headers = {
                    ["Content-Type"] = "application/json",
                    ["Content-Length"] = tostring(#json_str) 
                }
                
                -- Note: internet.request(url, data, headers, method)
                local handle, err = internet.request(config.serverUrl, json_str, headers, "POST")
                
                if handle then
                    print("Connection opened. Waiting for response...")
                    local result = ""
                    local count = 0
                    -- Read with small chunk size or line by line
                    for chunk in handle do 
                        result = result .. chunk 
                        count = count + 1
                    end
                    print("Server replied (" .. #result .. " bytes): " .. tostring(result))
                    handle:close()
                else
                    print("Connection failed: " .. tostring(err))
                end
            else
                print("Error: Internet card not found!")
            end
        else
            print("Error: No serverUrl configured!")
        end
    end

    local status, err = xpcall(cycle, debug.traceback)
    if not status then io.stderr:write("Error: " .. tostring(err) .. "\n") os.sleep(2) end

    local id = event.pull(config.pollInterval, "interrupted")
    if id == "interrupted" then running = false end
  end
end

local status, err = xpcall(main, debug.traceback)
if not status then io.stderr:write("Critical Error: " .. tostring(err) .. "\n") end
