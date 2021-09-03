local CheckButton = require("ui/widget/checkbutton")
local UIManager = require("ui/uimanager")
local _ = require("gettext")

local input_dialog, check_button_bold, check_button_border, check_button_compact

local sub_item_table = {
    {
        text = _("Keyboard font size"),
        keep_menu_open = true,
        callback = function()
            input_dialog = require("ui/widget/inputdialog"):new{
                title = _("Keyboard font size"),
                input = tostring(G_reader_settings:readSetting("keyboard_key_font_size") or 22),
                input_hint = "(16 - 30)",
                buttons = {
                    {
                        {
                            text = _("Close"),
                            callback = function()
                                UIManager:close(input_dialog)
                            end,
                        },
                        {
                            text = _("Apply"),
                            is_enter_default = true,
                            callback = function()
                                local font_size = tonumber(input_dialog:getInputText())
                                if font_size and font_size >= 16 and font_size <= 30 then
                                    G_reader_settings:saveSetting("keyboard_key_font_size", font_size)
                                    G_reader_settings:saveSetting("keyboard_key_bold", check_button_bold.checked)
                                    G_reader_settings:saveSetting("keyboard_key_border", check_button_border.checked)
                                    G_reader_settings:saveSetting("keyboard_key_compact", check_button_compact.checked)
                                    input_dialog._input_widget:onCloseKeyboard()
                                    input_dialog._input_widget:initKeyboard()
                                    input_dialog:onShowKeyboard()
                                end
                            end,
                        },
                    },
                },
            }

            check_button_bold = CheckButton:new{
                text = _("in bold"),
                checked = G_reader_settings:isTrue("keyboard_key_bold"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_bold:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_bold)
            check_button_border = CheckButton:new{
                text = _("with border"),
                checked = G_reader_settings:nilOrTrue("keyboard_key_border"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_border:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_border)
            check_button_compact = CheckButton:new{
                text = _("compact"),
                checked = G_reader_settings:isTrue("keyboard_key_compact"),
                parent = input_dialog,
                max_width = input_dialog._input_widget.width,
                callback = function()
                    check_button_compact:toggleCheck()
                end,
            }
            input_dialog:addWidget(check_button_compact)

            UIManager:show(input_dialog)
            input_dialog:onShowKeyboard()
        end,
    },
}

return sub_item_table
