-- upload_config.lua
-- Utility to upload config.lua to Pastebin from OpenComputers
-- Usage: send_config [config_path]
-- If no path is provided, defaults to /home/config.lua

local shell = require("shell")
local args, options = shell.parse(...)
local configPath = args[1] or "/home/recipes_config.lua"

print("Uploading file to Pastebin...")
local result = shell.execute("pastebin put " .. configPath)
print("\n")
if result then
  print("Upload complete. Check above for your Pastebin link.")
else
  print("Upload failed. Make sure pastebin program is installed and HTTP is enabled.")
end