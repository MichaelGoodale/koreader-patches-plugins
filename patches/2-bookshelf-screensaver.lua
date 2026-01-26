local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")

local Screen = Device.screen

local function getBookColor(index)
    local shades = {
        Blitbuffer.Color8(0x30),
        Blitbuffer.Color8(0x70),
        Blitbuffer.Color8(0x50),
        Blitbuffer.Color8(0xB0),
        Blitbuffer.Color8(0x90),
    }
    return shades[((index - 1) % #shades) + 1]
end

local function buildBookshelfWidget()
    local screen_size = Screen:getSize()

    local num_books = 5
    local books_group = HorizontalGroup:new {
        align = "bottom",
    }

    local max_height = 0

    for i = 1, num_books do
        local spine_width = Screen:scaleBySize(math.random(80, 100))
        local height_percent = 0.7 + (math.random() * 0.15) -- 70-85%
        local spine_height = math.floor(screen_size.h * height_percent)

        max_height = math.max(max_height, spine_height)

        local base_color = getBookColor(i)
        local accent_color = Blitbuffer.Color8(math.min(0xFF, base_color.a + 0x50))

        local progress = math.random(10, 95)
        local progress_height = math.floor(spine_height * (progress / 100))

        local spine_content = VerticalGroup:new {
            align = "center",
            -- Progress bar (fills from top based on % read)
            FrameContainer:new {
                width = spine_width,
                height = progress_height,
                background = accent_color,
                bordersize = 0,
                VerticalSpan:new { width = progress_height },
            },
            -- Remaining space
            FrameContainer:new {
                width = spine_width,
                height = spine_height - progress_height,
                background = base_color,
                bordersize = 0,
                VerticalSpan:new { width = spine_height - progress_height },
            }
        }

        local spine = FrameContainer:new {
            width = spine_width,
            height = spine_height,
            background = getBookColor(i),
            bordersize = 1,
            color = Blitbuffer.COLOR_BLACK,
            -- padding = 0,
            spine_content,
        }

        table.insert(books_group, spine)

        if i < num_books then
            table.insert(books_group, HorizontalSpan:new { width = spine_width + Screen:scaleBySize(math.random(1, 4)) })
        end
    end

    return OverlapGroup:new {
        dimen = screen_size,
        VerticalGroup:new {
            VerticalSpan:new {
                width = screen_size.h - max_height - Screen:scaleBySize(20),
            },
            HorizontalGroup:new {
                HorizontalSpan:new { width = Screen:scaleBySize(20) },
                books_group
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

    self.screensaver_widget = ScreenSaverWidget:new {
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
