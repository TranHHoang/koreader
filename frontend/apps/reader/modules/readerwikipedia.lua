local BD = require("ui/bidi")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LuaData = require("luadata")
local NetworkMgr = require("ui/network/manager")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local Trapper = require("ui/trapper")
local Translator = require("ui/translator")
local UIManager = require("ui/uimanager")
local Wikipedia = require("ui/wikipedia")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util  = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local wikipedia_history = nil

-- Wikipedia as a special dictionary
local ReaderWikipedia = ReaderDictionary:extend{
    -- identify itself
    is_wiki = true,
    wiki_languages = {},
    disable_history = G_reader_settings:isTrue("wikipedia_disable_history"),
}

function ReaderWikipedia:init()
    self.ui.menu:registerToMainMenu(self)
    if not wikipedia_history then
        wikipedia_history = LuaData:open(DataStorage:getSettingsDir() .. "/wikipedia_history.lua", { name = "WikipediaHistory" })
    end
end

function ReaderWikipedia:lookupInput()
    self.input_dialog = InputDialog:new{
        title = _("Enter a word or phrase to look up"),
        input = "",
        input_type = "text",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    callback = function()
                        UIManager:close(self.input_dialog)
                    end,
                },
                {
                    text = _("Search Wikipedia"),
                    is_enter_default = true,
                    callback = function()
                        if self.input_dialog:getInputText() == "" then return end
                        UIManager:close(self.input_dialog)
                        -- Trust that input text does not need any cleaning (allows querying for "-suffix")
                        self:onLookupWikipedia(self.input_dialog:getInputText(), true)
                    end,
                },
            }
        },
    }
    UIManager:show(self.input_dialog)
    self.input_dialog:onShowKeyboard()
end

function ReaderWikipedia:addToMainMenu(menu_items)
    menu_items.wikipedia_lookup =  {
        text = _("Wikipedia lookup"),
        callback = function() self:onShowWikipediaLookup() end,
    }
    menu_items.wikipedia_settings = {
        text = _("Wikipedia settings"),
        sub_item_table = {
            {
                text = _("Enable Wikipedia history"),
                checked_func = function()
                    return not self.disable_history
                end,
                callback = function()
                    self.disable_history = not self.disable_history
                    G_reader_settings:saveSetting("wikipedia_disable_history", self.disable_history)
                end,
            },
            {
                text = _("Clean Wikipedia history"),
                enabled_func = function()
                    return wikipedia_history:has("wikipedia_history")
                end,
                keep_menu_open = true,
                callback = function(touchmenu_instance)
                    UIManager:show(ConfirmBox:new{
                        text = _("Clean Wikipedia history?"),
                        ok_text = _("Clean"),
                        ok_callback = function()
                            -- empty data table to replace current one
                            wikipedia_history:reset{}
                            touchmenu_instance:updateItems()
                        end,
                    })
                end,
                separator = true,
            },
            { -- setting used in wikipedia.lua
                text = _("Show image in search results"),
                checked_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("wikipedia_show_image")
                end,
            },
            { -- setting used in wikipedia.lua
                text = _("Show more images in full article"),
                enabled_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                checked_func = function()
                    return G_reader_settings:nilOrTrue("wikipedia_show_more_images") and G_reader_settings:nilOrTrue("wikipedia_show_image")
                end,
                callback = function()
                    G_reader_settings:flipNilOrTrue("wikipedia_show_more_images")
                end,
            },
        }
    }
end

function ReaderWikipedia:initLanguages(word)
    if #self.wiki_languages > 0 then -- already done
        return
    end
    -- Fill self.wiki_languages with languages to propose
    local wikipedia_languages = G_reader_settings:readSetting("wikipedia_languages")
    if type(wikipedia_languages) == "table" and #wikipedia_languages > 0 then
        -- use this setting, no need to guess
        self.wiki_languages = wikipedia_languages
    else
        -- guess some languages
        self.seen_lang = {}
        local addLanguage = function(lang)
            if lang and lang ~= "" then
                -- convert "zh-CN" and "zh-TW" to "zh"
                lang = lang:match("(.*)-") or lang
                if lang == "C" then lang="en" end
                lang = lang:lower()
                if not self.seen_lang[lang] then
                    table.insert(self.wiki_languages, lang)
                    self.seen_lang[lang] = true
                end
            end
        end
        -- use book and UI languages
        if self.view then
            addLanguage(self.view.document:getProps().language)
        end
        addLanguage(G_reader_settings:readSetting("language"))
        if #self.wiki_languages == 0 and word then
            -- if no language at all, do a translation of selected word
            local ok_translator, lang
            ok_translator, lang = pcall(Translator.detect, Translator, word)
            if ok_translator then
                addLanguage(lang)
            end
        end
        -- add english anyway, so we have at least one language
        addLanguage("en")
    end
end

function ReaderWikipedia:onLookupWikipedia(word, is_sane, box, get_fullpage, forced_lang)
    -- Wrapped through Trapper, as we may be using Trapper:dismissableRunInSubprocess() in it
    Trapper:wrap(function()
        self:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang)
    end)
    return true
end

function ReaderWikipedia:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang)
    if NetworkMgr:willRerunWhenOnline(function() self:lookupWikipedia(word, is_sane, box, get_fullpage, forced_lang) end) then
        -- Not online yet, nothing more to do here, NetworkMgr will forward the callback and run it once connected!
        return
    end

    -- word is the text to query. If get_fullpage is true, it is the
    -- exact wikipedia page title we want the full page of.
    self:initLanguages(word)
    local lang
    if forced_lang then
        -- use provided lang (from readerlink when noticing that an external link is a wikipedia url)
        lang = forced_lang
    else
        -- use first lang from self.wiki_languages, which may have been rotated by DictQuickLookup
        lang = self.wiki_languages[1]
    end
    logger.dbg("lookup word:", word, box, get_fullpage)
    -- no need to clean word if get_fullpage, as it is the exact wikipetia page title
    if word and not get_fullpage then
        -- escape quotes and other funny characters in word
        word = self:cleanSelection(word, is_sane)
        -- no need to lower() word with wikipedia search
    end
    logger.dbg("stripped word:", word)
    if word == "" then
        return
    end
    local display_word = word:gsub("_", " ")

    if not self.disable_history then
        local book_title = self.ui.doc_settings and self.ui.doc_settings:readSetting("doc_props").title or _("Wikipedia lookup")
        if book_title == "" then -- no or empty metadata title
            if self.ui.document and self.ui.document.file then
                local directory, filename = util.splitFilePathName(self.ui.document.file) -- luacheck: no unused
                book_title = util.splitFileNameSuffix(filename)
            end
        end
        wikipedia_history:addTableItem("wikipedia_history", {
            book_title = book_title,
            time = os.time(),
            word = display_word,
            lang = lang:lower(),
            page = get_fullpage,
        })
    end

    -- Fix lookup message to include lang and set appropriate error texts
    local no_result_text, req_failure_text
    if get_fullpage then
        self.lookup_msg = T(_("Retrieving Wikipedia %2 article:\n%1"), "%1", lang:upper())
        req_failure_text = _("Failed to retrieve Wikipedia article.")
        no_result_text = _("Wikipedia article not found.")
    else
        self.lookup_msg = T(_("Searching Wikipedia %2 for:\n%1"), "%1", lang:upper())
        req_failure_text = _("Failed searching Wikipedia.")
        no_result_text = _("No results.")
    end
    self:showLookupInfo(display_word)

    local results = {}
    local ok, pages
    local lookup_cancelled = false
    Wikipedia:setTrapWidget(self.lookup_progress_msg)
    if get_fullpage then
        ok, pages = pcall(Wikipedia.getFullPage, Wikipedia, word, lang)
    else
        ok, pages = pcall(Wikipedia.searchAndGetIntros, Wikipedia, word, lang)
    end
    Wikipedia:resetTrapWidget()
    if not ok and pages and string.find(pages, Wikipedia.dismissed_error_code) then
        -- So we can display an alternate dummy result
        lookup_cancelled = true
        -- Or we could just not show anything with:
        -- self:dismissLookupInfo()
        -- return
    end
    if ok and pages then
        -- sort pages according to 'index' attribute if present (not present
        -- in fullpage results)
        local sorted_pages = {}
        local has_indexes = false
        for pageid, page in pairs(pages) do
            if page.index ~= nil then
                sorted_pages[page.index+1] = page
                has_indexes = true
            end
        end
        if has_indexes then
            pages = sorted_pages
        end
        for pageid, page in pairs(pages) do
            local definition = page.extract or no_result_text
            if page.length then
                -- we get 'length' only for intro results
                -- let's append it to definition so we know
                -- how big/valuable the full page is
                local fullkb = math.ceil(page.length/1024)
                local more_factor = math.ceil( page.length / (1+definition:len()) ) -- +1 just in case len()=0
                definition = definition .. "\n" .. T(_("(full article : %1 kB, = %2 x this intro length)"), fullkb, more_factor)
            end
            local result = {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = page.title,
                definition = definition,
                is_wiki_fullpage = get_fullpage,
                lang = lang,
                rtl_lang = Wikipedia:isWikipediaLanguageRTL(lang),
                images = page.images,
            }
            table.insert(results, result)
        end
        -- logger.dbg of results will be done by ReaderDictionary:showDict()
    else
        -- dummy results
        local definition
        if lookup_cancelled then
            definition = _("Wikipedia request interrupted.")
        elseif ok then
            definition = no_result_text
        else
            definition = req_failure_text
            logger.dbg("error:", pages)
        end
        results = {
            {
                dict = T(_("Wikipedia %1"), lang:upper()),
                word = word,
                definition = definition,
                is_wiki_fullpage = get_fullpage,
                lang = lang,
            }
        }
        logger.dbg("dummy result table:", word, results)
    end
    self:showDict(word, results, box)
end

-- override onSaveSettings in ReaderDictionary
function ReaderWikipedia:onSaveSettings()
end

function ReaderWikipedia:onShowWikipediaLookup()
    local connect_callback = function()
        self:lookupInput()
    end
    NetworkMgr:runWhenOnline(connect_callback)
    return true
end

return ReaderWikipedia
