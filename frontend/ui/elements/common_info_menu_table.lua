local Device = require("device")
local Event = require("ui/event")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local common_info = {}

common_info.more_tools = {
    text = _("More tools"),
}

-- common_info.device = {
--     text = _("Device"),
-- }

return common_info
