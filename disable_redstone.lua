-- Disable all redstone outputs on all redstone I/O blocks
local component = require("component")

print("Disabling all redstone outputs...")

local count = 0
for address, _ in component.list("redstone") do
    local proxy = component.proxy(address)
    for side = 0, 5 do
        proxy.setOutput(side, 0)
    end
    count = count + 1
    print("Disabled: " .. address:sub(1, 8) .. "...")
end

print("\nDone. Disabled " .. count .. " redstone I/O block(s).")
