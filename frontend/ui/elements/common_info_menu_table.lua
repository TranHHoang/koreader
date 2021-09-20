local Device = require("device")
local Event = require("ui/event")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local common_info = {}

common_info.more_tools = {
    text = _("More tools"),
}

-- common_info.device = {
--     text = _("Device"),
-- }

if Device:canSuspend() then
    common_info.sleep = {
        text = _("Sleep"),
        callback = function()
            UIManager:suspend()
        end,
    }
end
if Device:canReboot() then
    common_info.reboot = {
        text = _("Reboot the device"),
        keep_menu_open = true,
        callback = function()
            UIManager:broadcastEvent(Event:new("Reboot"))
        end
    }
end
if Device:canPowerOff() then
    common_info.poweroff = {
        text = _("Power off"),
        keep_menu_open = true,
        callback = function()
            UIManager:broadcastEvent(Event:new("PowerOff"))
        end
    }
end

return common_info
