local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local CheckButton = require("ui/widget/checkbutton")
local ConfirmBox = require("ui/widget/confirmbox")
local Device = require("device")
local DeviceListener = require("device/devicelistener")
local DocSettings = require("docsettings")
local DocumentRegistry = require("document/documentregistry")
local Event = require("ui/event")
local FileChooser = require("ui/widget/filechooser")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local FileManagerConverter = require("apps/filemanager/filemanagerconverter")
local FileManagerFileSearcher = require("apps/filemanager/filemanagerfilesearcher")
local FileManagerHistory = require("apps/filemanager/filemanagerhistory")
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerShortcuts = require("apps/filemanager/filemanagershortcuts")
local FrameContainer = require("ui/widget/container/framecontainer")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LanguageSupport = require("languagesupport")
local MultiConfirmBox = require("ui/widget/multiconfirmbox")
local PluginLoader = require("pluginloader")
local ReadCollection = require("readcollection")
local ReaderDeviceStatus = require("apps/reader/modules/readerdevicestatus")
local ReaderDictionary = require("apps/reader/modules/readerdictionary")
local ReaderWikipedia = require("apps/reader/modules/readerwikipedia")
local ReaderGoogleSearch = require("apps/reader/modules/readergooglesearch")
local Screenshoter = require("ui/widget/screenshoter")
local VerticalGroup = require("ui/widget/verticalgroup")
local UIManager = require("ui/uimanager")
local filemanagerutil = require("apps/filemanager/filemanagerutil")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local BaseUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local C_ = _.pgettext
local N_ = _.ngettext
local Screen = Device.screen
local T = BaseUtil.template
local Button = require("ui/widget/button")
local Font = require("ui/font")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local IconButton = require("ui/widget/iconbutton")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")

local FileManager = InputContainer:extend {
    title = _("KOReader"),
    active_widgets = nil, -- array
    root_path = lfs.currentdir(),

    clipboard = nil, -- for single file operations
    selected_files = nil, -- for group file operations

    mv_bin = Device:isAndroid() and "/system/bin/mv" or "/bin/mv",
    cp_bin = Device:isAndroid() and "/system/bin/cp" or "/bin/cp",
}

function FileManager:onSetRotationMode(rotation)
    if rotation ~= nil and rotation ~= Screen:getRotationMode() then
        Screen:setRotationMode(rotation)
        if FileManager.instance then
            self:reinit(self.path, self.focused_file)
        end
    end
    return true
end

function FileManager:onPhysicalKeyboardConnected()
    -- So that the key navigation shortcuts apply right away.
    -- This will also naturally call registerKeyEvents
    self:reinit(self.path, self.focused_file)
end
FileManager.onPhysicalKeyboardDisconnected = FileManager.onPhysicalKeyboardConnected

function FileManager:setRotationMode()
    local locked = G_reader_settings:isTrue("lock_rotation")
    if not locked then
        local rotation_mode = G_reader_settings:readSetting("fm_rotation_mode") or Screen.DEVICE_ROTATED_UPRIGHT
        self:onSetRotationMode(rotation_mode)
    end
end

function FileManager:initGesListener()
    if not Device:isTouchDevice() then
        return
    end

    self:registerTouchZones({
        {
            id = "filemanager_swipe",
            ges = "swipe",
            screen_zone = {
                ratio_x = 0, ratio_y = 0,
                ratio_w = Screen:getWidth(), ratio_h = Screen:getHeight(),
            },
            handler = function(ges)
                self:onSwipeFM(ges)
            end,
        },
    })
end

function FileManager:onSetDimensions(dimen)
    -- update listening according to new screen dimen
    if Device:isTouchDevice() then
        self:updateTouchZonesOnScreenResize(dimen)
    end
end

local function split(inputstr, sep)
    if sep == nil then
        sep = "%s"
    end
    local t = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(t, str)
    end
    return t
end

function FileManager:setupLayout()
    self.show_parent = self.show_parent or self
    local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir() or ""

    local icon_size = Screen:scaleBySize(24)
    local up_button = IconButton:new {
        icon = home_dir == self.root_path and "up" or "home",
        bordersize = 0,
        width = icon_size, -- our icons are square
        height = icon_size,
        padding_left = Size.padding.default,
        padding_right = Size.padding.default,
        callback = function()
            if home_dir == self.root_path then
                self.file_chooser:onFolderUp()
            else
                self:goHome()
            end
        end,
    }
    self.plus_button = IconButton:new {
        icon = "plus",
        bordersize = 0,
        width = icon_size, -- our icons are square
        height = icon_size,
        callback = function()
            self:onShowPlusMenu()
        end,
    }

    local WidgetContainer = require("ui/widget/container/widgetcontainer")

    self.path_group = HorizontalGroup:new {}
    local paths = split(self.root_path:gsub(home_dir, "Home"), "/")

    for k, v in pairs(paths) do
        if (v ~= "Home" or #paths == 1) and k >= math.max(#paths - 3, 0) then
            local separator = TextWidget:new {
                face = Font:getFace("smallinfofont", 20),
                bold = "true",
                text = " › ",
            }
            table.insert(self.path_group, Button:new {
                text = v,
                padding = 0,
                avoid_text_truncation = false,
                max_width = (Screen:getWidth() - 2 * icon_size - separator:getSize().w * #paths) /
                    (#paths - (paths[1] == "Home" and 1 or 0)),
                bordersize = 0,
                text_font_bold = false,
                text_font_size = 18,
                callback = function()
                    local path = table.concat({ unpack(paths, 1, k) }, "/"):gsub("Home", home_dir)
                    self.file_chooser:changeToPath("/" .. path)
                end,
            })
            table.insert(self.path_group, separator)
        end
    end

    self.banner = FrameContainer:new {
        padding = Size.padding.tiny,
        bordersize = 0,
        WidgetContainer:new {
            dimen = { w = Screen:getWidth(), h = self.path_group:getSize().h },
            HorizontalGroup:new {
                up_button,
                WidgetContainer:new {
                    dimen = {
                        w = Screen:getWidth() - 2 * icon_size - 4 * Size.padding.default,
                        h = self.path_group:getSize().h,
                    },
                    self.path_group,
                },
                self.plus_button,
            }
        },
    }

    -- logger.dbg("AAAAAAAAAAAAAA", self.banner[1][1]:getSize())

    local show_hidden = G_reader_settings:isTrue("show_hidden") or G_defaults:readSetting("DSHOWHIDDENFILES")
    local show_unsupported = G_reader_settings:isTrue("show_unsupported")
    local file_chooser = FileChooser:new {
        -- remember to adjust the height when new item is added to the group
        path = self.root_path,
        focused_path = self.focused_file,
        show_parent = self.show_parent,
        show_hidden = show_hidden,
        width = Screen:getWidth(),
        height = Screen:getHeight() - self.banner:getSize().h,
        is_popout = false,
        is_borderless = true,
        show_hidden = show_hidden,
        show_unsupported = show_unsupported,
        file_filter = function(filename)
            if DocumentRegistry:hasProvider(filename) then
                return true
            end
        end,
        close_callback = function() return self:onClose() end,
        -- allow left bottom tap gesture, otherwise it is eaten by hidden return button
        return_arrow_propagation = true,
        -- allow Menu widget to delegate handling of some gestures to GestureManager
        filemanager = self,
    }
    self.file_chooser = file_chooser
    self.focused_file = nil -- use it only once

    local file_manager = self

    function file_chooser:onPathChanged(path) -- luacheck: ignore
        local fm = FileManager.instance
        fm:reinit(path, nil)
        UIManager:setDirty(fm.banner, "ui", fm.banner.dimen)
    end

    function file_chooser:onFileSelect(file) -- luacheck: ignore
        if file_manager.select_mode then
            if file_manager.selected_files[file] then
                file_manager.selected_files[file] = nil
            else
                file_manager.selected_files[file] = true
            end
            self:refreshPath()
        else
            local ReaderUI = require("apps/reader/readerui")
            ReaderUI:showReader(file)
        end
        return true
    end

    function file_chooser:onFileHold(file)
        if file_manager.select_mode then
            file_manager:tapPlus()
        else
            self:showFileDialog(file)
        end
    end

    function file_chooser:showFileDialog(file) -- luacheck: ignore
        local is_file = lfs.attributes(file, "mode") == "file"
        local is_folder = lfs.attributes(file, "mode") == "directory"
        local is_not_parent_folder = BaseUtil.basename(file) ~= ".."
        local buttons = {
            {
                {
                    text = C_("File", " Copy"), -- Copy
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:copyFile(file)
                    end,
                },
                {
                    text = C_("File", " Paste"), -- Paste
                    enabled = file_manager.clipboard and true or false,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:pasteHere(file)
                    end,
                },
                {
                    text = _("Select"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:onToggleSelectMode(true) -- no full screen refresh
                        if is_file then
                            file_manager.selected_files[file] = true
                            self:refreshPath()
                        end
                    end,
                },
            },
            {
                {
                    text = _(" Cut"), -- Cut
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:cutFile(file)
                    end,
                },
                {
                    text = _("﯊ Delete"), -- Delete
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        local function post_delete_callback()
                            self:refreshPath()
                        end
                        file_manager:showDeleteFileDialog(file, post_delete_callback)
                    end,
                },
                {
                    text = _("凜 Rename"), -- Rename
                    enabled = is_not_parent_folder,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:showRenameFileDialog(file, is_file)
                    end,
                }
            },
            {}, -- separator
        }

        if is_file then
            local function close_dialog_callback()
                UIManager:close(self.file_dialog)
            end
            local function status_button_callback()
                UIManager:close(self.file_dialog)
                self:refreshPath() -- sidecar folder may be created/deleted
            end
            local has_provider = DocumentRegistry:getProviders(file) ~= nil
            if has_provider or DocSettings:hasSidecarFile(file) then
                table.insert(buttons, filemanagerutil.genStatusButtonsRow(file, status_button_callback))
                table.insert(buttons, {}) -- separator
            end
            table.insert(buttons, {
                filemanagerutil.genResetSettingsButton(file, status_button_callback),
                {
                    text_func = function()
                        return ReadCollection:checkItemExist(file)
                            and _("Remove from favorites") or _("Add to favorites")
                    end,
                    enabled = has_provider,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        if ReadCollection:checkItemExist(file) then
                            ReadCollection:removeItem(file)
                        else
                            ReadCollection:addItem(file)
                        end
                    end,
                },
            })
            table.insert(buttons, {
                {
                    text = _("Open with…"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        local one_time_providers = {
                            {
                                provider_name = _("Text viewer"),
                                callback = function()
                                    file_manager:openTextViewer(file)
                                end,
                            },
                        }
                        if file_manager.texteditor then
                            table.insert(one_time_providers, {
                                provider_name = _("Text editor"),
                                callback = function()
                                    file_manager.texteditor:checkEditFile(file)
                                end,
                            })
                        end
                        self:showSetProviderButtons(file, one_time_providers)
                    end,
                },
                filemanagerutil.genBookInformationButton(file, close_dialog_callback),
            })
            table.insert(buttons, {
                filemanagerutil.genBookCoverButton(file, close_dialog_callback),
                filemanagerutil.genBookDescriptionButton(file, close_dialog_callback),
            })
            if Device:canExecuteScript(file) then
                table.insert(buttons, {
                    filemanagerutil.genExecuteScriptButton(file, close_dialog_callback),
                })
            end
            if FileManagerConverter:isSupported(file) then
                table.insert(buttons, {
                    {
                        text = _("Convert"),
                        callback = function()
                            UIManager:close(self.file_dialog)
                            FileManagerConverter:showConvertButtons(file, self)
                        end,
                    },
                })
            end
        end

        if is_folder then
            table.insert(buttons, {
                {
                    text = _(" Set as Home folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        file_manager:setHome(BaseUtil.realpath(file))
                    end
                },
            })
        end

        self.file_dialog = ButtonDialogTitle:new{
            title = is_file and BD.filename(file:match("([^/]+)$")) or BD.directory(file:match("([^/]+)$")),
            title_align = "center",
            buttons = buttons,
        }
        UIManager:show(self.file_dialog)
        return true
    end

    self.layout = VerticalGroup:new {
        self.banner,
        file_chooser,
    }

    local fm_ui = FrameContainer:new {
        padding = 0,
        bordersize = 0,
        background = Blitbuffer.COLOR_WHITE,
        self.layout,
    }

    self[1] = fm_ui

    self.menu = FileManagerMenu:new {
        ui = self
    }

    self:registerKeyEvents()
end

function FileManager:registerKeyEvents()
    -- NOTE: We need to be surgical here, because this is called through reinit at runtime.
    if Device:hasKeys() then
        self.key_events.Home = { { "Home" } }
        -- Override the menu.lua way of handling the back key
        self.file_chooser.key_events.Back = { { Device.input.group.Back } }
        if not Device:hasFewKeys() then
            -- Also remove the handler assigned to the "Back" key by menu.lua
            self.file_chooser.key_events.Close = nil
        end
    else
        self.key_events.Home = nil
        self.file_chooser.key_events.Back = nil
        self.file_chooser.key_events.Close = nil
    end
end

function FileManager:registerModule(name, ui_module, always_active)
    if name then
        self[name] = ui_module
        ui_module.name = "filemanager" .. name
    end
    table.insert(self, ui_module)
    if always_active then
        -- to get events even when hidden
        table.insert(self.active_widgets, ui_module)
    end
end

-- NOTE: The only thing that will *ever* instantiate a new FileManager object is our very own showFiles below!
function FileManager:init()
    self:setupLayout()
    self.active_widgets = {}

    self:registerModule("screenshot", Screenshoter:new {
        prefix = 'FileManager',
        ui = self,
    }, true)

    self:registerModule("menu", self.menu)
    self:registerModule("history", FileManagerHistory:new { ui = self })
    self:registerModule("collections", FileManagerCollection:new { ui = self })
    self:registerModule("filesearcher", FileManagerFileSearcher:new { ui = self })
    self:registerModule("folder_shortcuts", FileManagerShortcuts:new { ui = self })
    self:registerModule("languagesupport", LanguageSupport:new { ui = self })
    self:registerModule("dictionary", ReaderDictionary:new { ui = self })
    self:registerModule("wikipedia", ReaderWikipedia:new { ui = self })
    self:registerModule("googlesearch", ReaderGoogleSearch:new { ui = self })
    self:registerModule("devicestatus", ReaderDeviceStatus:new { ui = self })
    self:registerModule("devicelistener", DeviceListener:new { ui = self })

    -- koreader plugins
    for _, plugin_module in ipairs(PluginLoader:loadPlugins()) do
        if not plugin_module.is_doc_only then
            local ok, plugin_or_err = PluginLoader:createPluginInstance(
                plugin_module, { ui = self, })
            -- Keep references to the modules which do not register into menu.
            if ok then
                self:registerModule(plugin_module.name, plugin_or_err)
                logger.dbg("FM loaded plugin", plugin_module.name,
                    "at", plugin_module.path)
            end
        end
    end

    if Device:hasWifiToggle() then
        local NetworkListener = require("ui/network/networklistener")
        table.insert(self, NetworkListener:new { ui = self })
    end

    self:initGesListener()
    self:handleEvent(Event:new("SetDimensions", self.dimen))

    -- NOTE: ReaderUI has a _getRunningInstance method for this, because it used to store the instance reference in a private module variable.
    if FileManager.instance == nil then
        logger.dbg("Spinning up new FileManager instance", tostring(self))
    else
        -- Should never happen, given what we did in showFiles...
        logger.err("FileManager instance mismatch! Opened", tostring(self), "while we still have an existing instance:",
            tostring(FileManager.instance), debug.traceback())
    end
    FileManager.instance = self
end

function FileChooser:onBack()
    local back_to_exit = G_reader_settings:readSetting("back_to_exit", "prompt")
    local back_in_filemanager = G_reader_settings:readSetting("back_in_filemanager", "default")
    if back_in_filemanager == "default" then
        if back_to_exit == "always" then
            return self:onClose()
        elseif back_to_exit == "disable" then
            return true
        elseif back_to_exit == "prompt" then
            UIManager:show(ConfirmBox:new {
                text = _("Exit KOReader?"),
                ok_text = _("Exit"),
                ok_callback = function()
                    self:onClose()
                end
            })

            return true
        end
    elseif back_in_filemanager == "parent_folder" then
        self:changeToPath(string.format("%s/..", self.path))
        return true
    end
end

function FileManager:onSwipeFM(ges)
    local direction = BD.flipDirectionIfMirroredUILayout(ges.direction)
    if direction == "west" then
        self.file_chooser:onNextPage()
    elseif direction == "east" then
        self.file_chooser:onPrevPage()
    end
    return true
end

function FileManager:onShowPlusMenu()
    self:tapPlus()
    return true
end

function FileManager:onToggleSelectMode(no_refresh)
    logger.dbg("toggle select mode")
    self.select_mode = not self.select_mode
    self.selected_files = self.select_mode and {} or nil
    self.plus_button:setIcon(self.select_mode and "check" or "plus")
    if not no_refresh then
        self:onRefresh()
    end
end

function FileManager:tapPlus()
    local title, buttons
    if self.select_mode then
        local select_count = util.tableSize(self.selected_files)
        local actions_enabled = select_count > 0
        title = actions_enabled and T(N_("1 file selected", "%1 files selected", select_count), select_count)
            or _("No files selected")
        buttons = {
            {
                {
                    text = _("礪"), -- Select all
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self.file_chooser:selectAllFilesInFolder()
                        self:onRefresh()
                    end,
                },
                {
                    text = _(""), -- Copy
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new {
                            text = _("Copy selected files to the current folder?"),
                            ok_text = _("Copy"),
                            ok_callback = function()
                                UIManager:close(self.file_dialog)
                                self.cutfile = false
                                for file in pairs(self.selected_files) do
                                    self.clipboard = file
                                    self:pasteHere(self.file_chooser.path)
                                end
                                self:onToggleSelectMode()
                            end,
                        })
                    end
                },
                {
                    text = _("ﱵ"), -- Deselect
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self.selected_files = {}
                        self:onRefresh()
                    end,
                },
                {
                    text = _(""), -- Move
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new {
                            text = _("Move selected files to the current folder?"),
                            ok_text = _("Move"),
                            ok_callback = function()
                                UIManager:close(self.file_dialog)
                                self.cutfile = true
                                for file in pairs(self.selected_files) do
                                    self.clipboard = file
                                    self:pasteHere(self.file_chooser.path)
                                end
                                self:onToggleSelectMode()
                            end,
                        })
                    end
                },
            },
            {
                {
                    text = _(""), -- Exit
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:onToggleSelectMode()
                    end,
                },
                {
                    text = _("﯊"), -- Delete
                    enabled = actions_enabled,
                    callback = function()
                        UIManager:show(ConfirmBox:new {
                            text = _("Delete selected files?\nIf you delete a file, it is permanently lost."),
                            ok_text = _("Delete"),
                            ok_callback = function()
                                UIManager:close(self.file_dialog)
                                for file in pairs(self.selected_files) do
                                    self:deleteFile(file, true) -- only files can be selected
                                end
                                self:onToggleSelectMode()
                            end,
                        })
                    end
                },
            },
            {}, -- separator
            {
                {
                    text = _("New folder"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:createFolder()
                    end,
                },
                {
                    text = _("Folder shortcuts"),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:handleEvent(Event:new("ShowFolderShortcutsDialog"))
                    end
                },
            },
        }
    else
        title = BD.dirpath(filemanagerutil.abbreviate(self.file_chooser.path))
        buttons = {
            {
                {
                    text = _("麗"), -- Select mode
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:onToggleSelectMode(true) -- no full screen refresh
                    end,
                },
                {
                    text = _(""), -- New folder
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:createFolder()
                    end,
                },
                {
                    text = _(""), -- Paste
                    enabled = self.clipboard and true or false,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:pasteHere(self.file_chooser.path)
                    end,
                },
                {
                    text = _(""), -- Set home
                    callback = function()
                        UIManager:close(self.file_dialog)
                        self:setHome(self.file_chooser.path)
                    end
                }
            },
        }

        if Device:hasExternalSD() then
            table.insert(buttons, 4, { -- after "Paste" or "Import files here" button
                {
                    text_func = function()
                        return Device:isValidPath(self.file_chooser.path)
                            and _("Switch to SDCard") or _("Switch to internal storage")
                    end,
                    callback = function()
                        UIManager:close(self.file_dialog)
                        if Device:isValidPath(self.file_chooser.path) then
                            local ok, sd_path = Device:hasExternalSD()
                            if ok then
                                self.file_chooser:changeToPath(sd_path)
                            end
                        else
                            self.file_chooser:changeToPath(Device.home_dir)
                        end
                    end,
                },
            })
        end

        if Device:canImportFiles() then
            table.insert(buttons, 4, { -- always after "Paste" button
                {
                    text = _("Import files here"),
                    enabled = Device:isValidPath(self.file_chooser.path),
                    callback = function()
                        UIManager:close(self.file_dialog)
                        Device.importFile(self.file_chooser.path)
                    end,
                },
            })
        end
    end

    self.file_dialog = ButtonDialogTitle:new {
        title = title,
        title_align = "center",
        buttons = buttons,
        select_mode = self.select_mode, -- for coverbrowser
    }
    UIManager:show(self.file_dialog)
end

function FileManager:reinit(path, focused_file)
    UIManager:flushSettings()
    self.dimen = Screen:getSize()
    -- backup the root path and path items
    self.root_path = path or self.file_chooser.path
    local path_items_backup = {}
    for k, v in pairs(self.file_chooser.path_items) do
        path_items_backup[k] = v
    end
    -- reinit filemanager
    self.focused_file = focused_file
    self:setupLayout()
    self:handleEvent(Event:new("SetDimensions", self.dimen))
    self.file_chooser.path_items = path_items_backup
    -- self:init() has already done file_chooser:refreshPath()
    -- (by virtue of rebuilding file_chooser), so this one
    -- looks unnecessary (cheap with classic mode, less cheap with
    -- CoverBrowser plugin's cover image renderings)
    -- self:onRefresh()
    if self.select_mode then
        self.plus_button:setIcon("check")
    end
end

function FileManager:getCurrentDir()
    return FileManager.instance and FileManager.instance.file_chooser.path
end

function FileManager:toggleHiddenFiles()
    self.file_chooser:toggleHiddenFiles()
    G_reader_settings:saveSetting("show_hidden", self.file_chooser.show_hidden)
end

function FileManager:toggleUnsupportedFiles()
    self.file_chooser:toggleUnsupportedFiles()
    G_reader_settings:saveSetting("show_unsupported", self.file_chooser.show_unsupported)
end

function FileManager:onClose()
    logger.dbg("close filemanager")
    PluginLoader:finalize()
    self:handleEvent(Event:new("SaveSettings"))
    G_reader_settings:flush()
    UIManager:close(self)
    return true
end

function FileManager:onCloseWidget()
    if FileManager.instance == self then
        logger.dbg("Tearing down FileManager", tostring(self))
    else
        logger.warn("FileManager instance mismatch! Closed", tostring(self), "while the active one is supposed to be",
            tostring(FileManager.instance))
    end
    FileManager.instance = nil
end

function FileManager:onShowingReader()
    -- Allows us to optimize out a few useless refreshes in various CloseWidgets handlers...
    self.tearing_down = true
    -- Clear the dither flag to prevent it from infecting the queue and re-inserting a full-screen refresh...
    self.dithered = nil

    self:onClose()
end

-- Same as above, except we don't close it yet. Useful for plugins that need to close custom Menus before calling showReader.
function FileManager:onSetupShowReader()
    self.tearing_down = true
    self.dithered = nil
end

function FileManager:onRefresh()
    self.file_chooser:refreshPath()
    return true
end

function FileManager:goHome()
    if not self.file_chooser:goHome() then
        self:setHome()
    end
    return true
end

function FileManager:setHome(path)
    path = path or self.file_chooser.path
    UIManager:show(ConfirmBox:new {
        text = T(_("Set '%1' as HOME folder?"), BD.dirpath(path)),
        ok_text = _("Set as HOME"),
        ok_callback = function()
            G_reader_settings:saveSetting("home_dir", path)
        end,
    })
    return true
end

function FileManager:openRandomFile(dir)
    local random_file = DocumentRegistry:getRandomFile(dir, false)
    if random_file then
        UIManager:show(MultiConfirmBox:new{
            text = T(_("Do you want to open %1?"), BD.filename(BaseUtil.basename(random_file))),
            choice1_text = _("Open"),
            choice1_callback = function()
                local ReaderUI = require("apps/reader/readerui")
                ReaderUI:showReader(random_file)
            end,
            -- @translators Another file. This is a button on the open random file dialog. It presents a file with the choices Open/Another.
            choice2_text = _("Another"),
            choice2_callback = function()
                self:openRandomFile(dir)
            end,
        })
    else
        UIManager:show(InfoMessage:new{
            text = _("File not found"),
        })
    end
end

function FileManager:copyFile(file)
    self.cutfile = false
    self.clipboard = file
end

function FileManager:cutFile(file)
    self.cutfile = true
    self.clipboard = file
end

function FileManager:pasteHere(file)
    local orig_file = BaseUtil.realpath(self.clipboard)
    local orig_name = BaseUtil.basename(self.clipboard)
    local dest_path = BaseUtil.realpath(file)
    dest_path = lfs.attributes(dest_path, "mode") == "directory" and dest_path or dest_path:match("(.*/)")
    local dest_file = BaseUtil.joinPath(dest_path, orig_name)
    local is_file = lfs.attributes(orig_file, "mode") == "file"

    local function infoCopyFile()
        if self:copyRecursive(orig_file, dest_path) then
            if is_file then
                DocSettings:update(orig_file, dest_file, true)
            end
            return true
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Failed to copy:\n%1\nto:\n%2"), BD.filepath(orig_name), BD.dirpath(dest_path)),
                icon = "notice-warning",
            })
        end
    end

    local function infoMoveFile()
        if self:moveFile(orig_file, dest_path) then
            if is_file then
                DocSettings:update(orig_file, dest_file)
                require("readhistory"):updateItemByPath(orig_file, dest_file) -- (will update "lastfile" if needed)
            end
            ReadCollection:updateItemByPath(orig_file, dest_file)
            return true
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Failed to move:\n%1\nto:\n%2"), BD.filepath(orig_name), BD.dirpath(dest_path)),
                icon = "notice-warning",
            })
        end
    end

    local function doPaste()
        local ok = self.cutfile and infoMoveFile() or infoCopyFile()
        if ok then
            self:onRefresh()
            self.clipboard = nil
        end
    end

    local mode = lfs.attributes(dest_file, "mode")
    if mode then
        UIManager:show(ConfirmBox:new{
            text = mode == "file" and T(_("File already exists:\n%1\nOverwrite file?"), BD.filename(orig_name))
                                   or T(_("Folder already exists:\n%1\nOverwrite folder?"), BD.directory(orig_name)),
            ok_text = _("Overwrite"),
            ok_callback = function()
                doPaste()
            end,
        })
    else
        doPaste()
    end
end

function FileManager:createFolder()
    local input_dialog, check_button_enter_folder
    input_dialog = InputDialog:new {
        title = _("New folder"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(input_dialog)
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local new_folder_name = input_dialog:getInputText()
                        if new_folder_name == "" then return end
                        UIManager:close(input_dialog)
                        local new_folder = string.format("%s/%s", self.file_chooser.path, new_folder_name)
                        if util.makePath(new_folder) then
                            if check_button_enter_folder.checked then
                                self.file_chooser:changeToPath(new_folder)
                            else
                                self.file_chooser:refreshPath()
                            end
                        else
                            UIManager:show(InfoMessage:new {
                                text = T(_("Failed to create folder:\n%1"), BD.directory(new_folder_name)),
                                icon = "notice-warning",
                            })
                        end
                    end,
                },
            }
        },
    }
    check_button_enter_folder = CheckButton:new {
        text = _("Enter folder after creation"),
        checked = false,
        parent = input_dialog,
    }
    input_dialog:addWidget(check_button_enter_folder)
    UIManager:show(input_dialog)
    input_dialog:onShowKeyboard()
end

function FileManager:showDeleteFileDialog(file, post_delete_callback, pre_delete_callback)
    local file_abs_path = BaseUtil.realpath(file)
    local is_file = lfs.attributes(file_abs_path, "mode") == "file"
    local text = (is_file and _("Delete file permanently?") or _("Delete folder permanently?")) .. "\n\n" .. BD.filepath(file)
    if is_file and DocSettings:hasSidecarFile(file_abs_path) then
        text = text .. "\n\n" .. _("Book settings, highlights and notes will be deleted.")
    end
    UIManager:show(ConfirmBox:new{
        text = text,
        ok_text = _("Delete"),
        ok_callback = function()
            if pre_delete_callback then
                pre_delete_callback()
            end
            if self:deleteFile(file, is_file) and post_delete_callback then
                post_delete_callback()
            end
        end,
    })
end

function FileManager:deleteFile(file, is_file)
    local file_abs_path = BaseUtil.realpath(file)
    if file_abs_path == nil then
        UIManager:show(InfoMessage:new {
            text = T(_("File not found:\n%1"), BD.filepath(file)),
            icon = "notice-warning",
        })
        return
    end

    local ok, err
    if is_file then
        ok, err = os.remove(file_abs_path)
    else
        ok, err = BaseUtil.purgeDir(file_abs_path)
    end
    if ok and not err then
        if is_file then
            DocSettings:update(file)
            require("readhistory"):fileDeleted(file)
        end
        ReadCollection:removeItemByPath(file, not is_file)
        return true
    else
        UIManager:show(InfoMessage:new {
            text = T(_("Failed to delete:\n%1"), BD.filepath(file)),
            icon = "notice-warning",
        })
    end
end

function FileManager:showRenameFileDialog(file, is_file)
    local dialog
    dialog = InputDialog:new{
        title = is_file and _("Rename file") or _("Rename folder"),
        input = BaseUtil.basename(file),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Rename"),
                callback = function()
                    local new_name = dialog:getInputText()
                    if new_name ~= "" then
                        UIManager:close(dialog)
                        self:renameFile(file, new_name, is_file)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function FileManager:renameFile(file, basename, is_file)
    if BaseUtil.basename(file) == basename then return end
    local dest = BaseUtil.joinPath(BaseUtil.dirname(file), basename)

    local function doRenameFile()
        if self:moveFile(file, dest) then
            if is_file then
                DocSettings:update(file, dest)
                require("readhistory"):updateItemByPath(file, dest) -- (will update "lastfile" if needed)
            end
            ReadCollection:updateItemByPath(file, dest)
            self:onRefresh()
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Failed to rename:\n%1\nto:\n%2"), BD.filepath(file), BD.filepath(dest)),
                icon = "notice-warning",
            })
        end
    end

    local mode_dest = lfs.attributes(dest, "mode")
    if mode_dest then
        local text, ok_text
        if (mode_dest == "file") ~= is_file then
            if is_file then
                text = T(_("Folder already exists:\n%1\nFile cannot be renamed."), BD.directory(basename))
            else
                text = T(_("File already exists:\n%1\nFolder cannot be renamed."), BD.filename(basename))
            end
            UIManager:show(InfoMessage:new{
                text = text,
                icon = "notice-warning",
            })
        else
            if is_file then
                text = T(_("File already exists:\n%1\nOverwrite file?"), BD.filename(basename))
                ok_text = _("Overwrite")
            else
                text = T(_("Folder already exists:\n%1\nMove the folder inside it?"), BD.directory(basename))
                ok_text = _("Move")
            end
            UIManager:show(ConfirmBox:new{
                text = text,
                ok_text = ok_text,
                ok_callback = function()
                    doRenameFile()
                end,
            })
        end
    else
        doRenameFile()
    end
end

function FileManager:getSortingMenuTable()
    local fm = self
    local collates = {
        strcoll = { _("File Name"), _("File name") },
        natural = { _("Natural"), _("File name (natural sorting)") },
        strcoll_mixed = { _("Name Mixed"), _("Name – mixed files and folders") },
        access = { _("Date Read"), _("Last read date") },
        change = { _("Date Added"), _("Date added") },
        modification = { _("Date Modified"), _("Date modified") },
        size = { _("Size"), _("Size") },
        type = { _("Type"), _("Type") },
        percent_unopened_first = { _("Unopened first"), _("Unopened first") },
        percent_unopened_last = { _("Unopened last"), _("Unopened last") },
    }
    local set_collate_table = function(collate)
        return {
            text = collates[collate][2],
            checked_func = function()
                return fm.file_chooser.collate == collate
            end,
            callback = function() fm:setCollate(collate) end,
        }
    end
    local get_collate_percent = function()
        local collate_type = G_reader_settings:readSetting("collate")
        if collate_type == "percent_unopened_first" or collate_type == "percent_unopened_last" then
            return collates[collate_type][2]
        else
            return _("Percent")
        end
    end
    return {
        text_func = function()
            return T(
                _("Sort by: %1"),
                collates[fm.file_chooser.collate][1]
            )
        end,
        sub_item_table = {
            {
                text = _("Name"),
                sub_item_table = {
                    set_collate_table("strcoll"),
                    set_collate_table("natural"),
                    set_collate_table("strcoll_mixed"),
                }
            },
            {
                text = _("Date"),
                sub_item_table = {
                    set_collate_table("access"),
                    set_collate_table("change"),
                    set_collate_table("modification"),
                }
            },
            {
                text = _("Others"),
                sub_item_table = {
                    set_collate_table("size"),
                    set_collate_table("type"),
                    {
                        text_func = get_collate_percent,
                        checked_func = function()
                            return fm.file_chooser.collate == "percent_unopened_first"
                                or fm.file_chooser.collate == "percent_unopened_last"
                        end,
                        sub_item_table = {
                            set_collate_table("percent_unopened_first"),
                            set_collate_table("percent_unopened_last"),
                        },
                    },
                },
                separator = true,
            },
        }
    }
end

function FileManager:getStartWithMenuTable()
    local start_with_setting = G_reader_settings:readSetting("start_with") or "filemanager"
    local start_withs = {
        filemanager = { _("File browser"), _("File browser") },
        history = { _("History"), _("History") },
        favorites = { _("Favorites"), _("Favorites") },
        folder_shortcuts = { _("Folder shortcuts"), _("Folder shortcuts") },
        last = { _("Last file"), _("Last file") },
    }
    local set_sw_table = function(start_with)
        return {
            text = start_withs[start_with][2],
            checked_func = function()
                return start_with_setting == start_with
            end,
            callback = function()
                start_with_setting = start_with
                G_reader_settings:saveSetting("start_with", start_with)
            end,
        }
    end
    return {
        text_func = function()
            return T(
                _("Start with: %1"),
                start_withs[start_with_setting][1]
            )
        end,
        sub_item_table = {
            set_sw_table("filemanager"),
            set_sw_table("history"),
            set_sw_table("favorites"),
            set_sw_table("folder_shortcuts"),
            set_sw_table("last"),
        }
    }
end

--- @note: This is the *only* safe way to instantiate a new FileManager instance!
function FileManager:showFiles(path, focused_file)
    -- Warn about and close any pre-existing FM instances first...
    if FileManager.instance then
        logger.warn("FileManager instance mismatch! Tried to spin up a new instance, while we still have an existing one:"
            , tostring(FileManager.instance))
        -- Close the old one first!
        FileManager.instance:onClose()
    end

    path = path or G_reader_settings:readSetting("lastdir") or filemanagerutil.getDefaultDir()
    G_reader_settings:saveSetting("lastdir", path)
    self:setRotationMode()
    local file_manager = FileManager:new {
        dimen = Screen:getSize(),
        covers_fullscreen = true, -- hint for UIManager:_repaint()
        root_path = path,
        focused_file = focused_file,
    }
    UIManager:show(file_manager)
end

function FileManager:openTextViewer(file_path)
    local function _openTextViewer(filepath)
        local file = io.open(filepath, "rb")
        if not file then return end
        local file_content = file:read("*all")
        file:close()
        UIManager:show(require("ui/widget/textviewer"):new {
            title = filepath,
            title_multilines = true,
            justified = false,
            text = file_content,
        })
    end

    local attr = lfs.attributes(file_path)
    if attr then
        if attr.size > 400000 then
            UIManager:show(ConfirmBox:new {
                text = T(_("This file is %2:\n\n%1\n\nAre you sure you want to open it?\n\nOpening big files may take some time.")
                    ,
                    BD.filepath(file_path), util.getFriendlySize(attr.size)),
                ok_text = _("Open"),
                ok_callback = function()
                    _openTextViewer(file_path)
                end,
            })
        else
            _openTextViewer(file_path)
        end
    end
end

--- A shortcut to execute mv.
-- @treturn boolean result of mv command
function FileManager:moveFile(from, to)
    return BaseUtil.execute(self.mv_bin, from, to) == 0
end

--- A shortcut to execute cp.
-- @treturn boolean result of cp command
function FileManager:copyFileFromTo(from, to)
    return BaseUtil.execute(self.cp_bin, from, to) == 0
end

--- A shortcut to execute cp recursively.
-- @treturn boolean result of cp command
function FileManager:copyRecursive(from, to)
    return BaseUtil.execute(self.cp_bin, "-r", from, to) == 0
end

function FileManager:onHome()
    return self:goHome()
end

function FileManager:onRefreshContent()
    self:onRefresh()
end

function FileManager:onShowFolderMenu()
    local button_dialog
    local function genButton(button_text, button_path)
        return {{
            text = button_text,
            align = "left",
            font_face = "smallinfofont",
            font_size = 22,
            font_bold = false,
            avoid_text_truncation = false,
            callback = function()
                UIManager:close(button_dialog)
                self.file_chooser:changeToPath(button_path)
            end,
            hold_callback = function()
                return true -- do not move the menu
            end,
        }}
    end

    local home_dir = G_reader_settings:readSetting("home_dir") or filemanagerutil.getDefaultDir()
    local home_dir_shortened = G_reader_settings:nilOrTrue("shorten_home_dir")
    local home_dir_not_locked = G_reader_settings:nilOrFalse("lock_home_folder")
    local home_dir_suffix = "  \u{f015}" -- "home" character
    local buttons = {}
    -- root folder
    local text
    local path = "/"
    local is_home = path == home_dir
    local home_found = is_home or home_dir_not_locked
    if home_found then
        text = path
        if is_home and home_dir_shortened then
            text = text .. home_dir_suffix
        end
        table.insert(buttons, genButton(text, path))
    end
    -- other folders
    local indent = ""
    for part in self.file_chooser.path:gmatch("([^/]+)") do
        text = (#buttons == 0 and path or indent .. "└ ") .. part
        path = path .. part .. "/"
        is_home = path == home_dir or path == home_dir .. "/"
        if not home_found and is_home then
            home_found = true
        end
        if home_found then
            if is_home and home_dir_shortened then
                text = text .. home_dir_suffix
            end
            table.insert(buttons, genButton(text, path))
            indent = indent .. " "
        end
    end

    button_dialog = ButtonDialog:new{
        width = math.floor(Screen:getWidth() * 0.9),
        shrink_unneeded_width = true,
        buttons = buttons,
        anchor = function()
            return self.title_bar.left_button.image.dimen
        end,
    }
    UIManager:show(button_dialog)
end

return FileManager
