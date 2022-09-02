local UIManager = require("ui/uimanager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local InputDialog = require("ui/widget/inputdialog")
local _ = require("gettext")
local NetworkMgr = require("ui/network/manager")
local Trapper = require("ui/trapper")
local logger = require("logger")
local GoogleSearch = require("ui/googlesearch")
local ffiutil = require("ffi/util")
local T = ffiutil.template

local ReaderGoogleSearch = ReaderDictionary:extend{
    is_google = true,
}

function ReaderGoogleSearch:init()
    self.ui.menu:registerToMainMenu(self)
    local settings = G_reader_settings:readSetting("google_custom_search")
    GoogleSearch.search_params.cx = settings.engine_id
    GoogleSearch.search_params.key = settings.api_key
end

function ReaderGoogleSearch:lookupInput()
    self.input_dialog = InputDialog:new{
        title = _("Enter a word or phrase to look up"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("ﰸ"), -- Cancel
                    id = "close",
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _(""), -- Search google
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        UIManager:close(self.input_dialog)
                        -- Trust that input text does not need any cleaning (allows querying for "-suffix")
                        self:onLookupGoogle(self.input_dialog:getInputText())
                    end,
                },
            }
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function ReaderGoogleSearch:addToMainMenu(menu_items)
    menu_items.googlesearch = {
        text = _("Google Search"),
        callback = function() self:onShowGoogleLookup() end,
    }
end

function ReaderGoogleSearch:onLookupGoogle(text, boxes)
    -- Wrapped through Trapper, as we may be using Trapper:dismissableRunInSubprocess() in it
    Trapper:wrap(function()
        self:lookupGoogle(text, boxes)
    end)
    return true
end

function ReaderGoogleSearch:lookupGoogle(text, boxes)
    if NetworkMgr:willRerunWhenOnline(function() self:lookupGoogle(text) end) then
        -- Not online yet, nothing more to do here, NetworkMgr will forward the callback and run it once connected!
        return
    end

    logger.dbg("lookup text:", text)
    -- Fix lookup message to include lang and set appropriate error texts
    self.lookup_msg = _("Searching Google for: %1")
    local req_failure_text = _("Failed searching Google.")
    local no_result_text = _("No results.")

    self:showLookupInfo(text)

    local search_result
    local lookup_cancelled = false
    GoogleSearch:setTrapWidget(self.lookup_progress_msg)
    local ok, result = pcall(GoogleSearch.searchAndGetResult, GoogleSearch, text)
    GoogleSearch:resetTrapWidget()

    if ok then
        local definition = ""
        for _, v in ipairs(result) do
            definition = definition..T("— %1\n", v.snippet)
        end
        definition = definition..""
        search_result = {
            dict = _("Google Search"),
            word = text,
            definition = definition,
        }
    else
        -- dummy results
        local definition
        if lookup_cancelled then
            definition = _("Google Search request interrupted.")
        elseif ok then
            definition = no_result_text
        else
            definition = req_failure_text
        end
        search_result = {
            dict = _("Google Search"),
            word = text,
            definition = definition,
        }
    end
    self:showDict(text, { search_result }, boxes)
end

function ReaderGoogleSearch:onShowGoogleLookup()
    local connect_callback = function()
        self:lookupInput()
    end
    NetworkMgr:runWhenOnline(connect_callback)
    return true
end

return ReaderGoogleSearch