local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")

local Screen = Device.screen

local function buildBookshelfWidget()
    local screen_size = Screen:getSize()

    local spine_width = Screen:scaleBySize(40)
    local spine_height = math.floor(screen_size.h * 0.8)

    local spine_content = VerticalSpan:new{
        width = spine_height,
    }

    local spine = FrameContainer:new{
        width = spine_width,
        height = spine_height,
        background = Blitbuffer.COLOR_BLACK,
        bordersize = 0,
        spine_content,
    }

    return OverlapGroup:new{
        dimen = screen_size,
        VerticalGroup:new{
            VerticalSpan:new{
                width = screen_size.h - spine_height,
            },
            HorizontalGroup:new{
                HorizontalSpan:new{ width = Screen:scaleBySize(20) },
                spine,
            },
        },
    }
end

local Screensaver = require("ui/screensaver")
local orig_screensaver_show = Screensaver.show

Screensaver.show = function(self)
    if self.screensaver_type ~= "bookshelf" then
        return orig_screensaver_show(self)
    end

    if self.screensaver_widget then
        UIManager:close(self.screensaver_widget)
        self.screensaver_widget = nil
    end

    Device.screen_saver_mode = true

    local widget = buildBookshelfWidget()

    self.screensaver_widget = ScreenSaverWidget:new{
        widget = widget,
        background = Blitbuffer.COLOR_WHITE,
        covers_fullscreen = true,
    }
    self.screensaver_widget.modal = true
    self.screensaver_widget.dithered = true

    UIManager:show(self.screensaver_widget, "full")
end

local orig_dofile = dofile
_G.dofile = function(filepath)
    local result = orig_dofile(filepath)
    if filepath and filepath:match("screensaver_menu%.lua$") then
        if result and result[1] and result[1].sub_item_table then
            local wallpaper_submenu = result[1].sub_item_table

            table.insert(wallpaper_submenu, {
                text = "Bookshelf",
                checked_func = function()
                    return G_reader_settings:readSetting("screensaver_type") == "bookshelf"
                end,
                callback = function()
                    G_reader_settings:saveSetting("screensaver_type", "bookshelf")
                end,
                radio = true,
            })
        end
    end
    return result
end
