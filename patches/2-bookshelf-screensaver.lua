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
        Blitbuffer.Color8(0xA0),
        Blitbuffer.Color8(0x80),
        Blitbuffer.Color8(0xB0),
        Blitbuffer.Color8(0x90),
    }
    return shades[((index - 1) % #shades) + 1]
end

local function buildBookshelfWidget()
    local screen_size = Screen:getSize()

    -- fake book data
    local books = {
        { title = "Neuromancer", author = "William Gibson" },
        { title = "Foundation",  author = "Isaac Asimov" },
        { title = "Dune",        author = "Frank Herbert" },
        { title = "1984",        author = "George Orwell" },
        { title = "The Hobbit",  author = "J.R.R. Tolkien" },
    }

    local num_books = 5
    local books_stack = VerticalGroup:new {
        align = "left",
    }

    local max_width = 0
    local total_height = 0
    local spacing = Screen:scaleBySize(3)

    for i = 1, num_books do
        local book = books[i]
        -- book thickness
        local book_height = Screen:scaleBySize(math.random(90, 120))
        local height_percent = 0.8 + (math.random() * 0.15) -- 80-95%
        local book_width = math.floor(screen_size.w * height_percent)

        max_width = math.max(max_width, book_width)
        total_height = total_height + book_height

        local base_color = getBookColor(i)
        local accent_color = Blitbuffer.Color8(math.min(0xFF, base_color.a + 0x50))

        local progress = math.random(10, 95)
        local progress_width = math.floor(book_width * (progress / 100))

        local title_face = Font:getFace("cfont", Screen:scaleBySize(12))
        local author_face = Font:getFace("cfont", Screen:scaleBySize(9))

        local title_widget = TextWidget:new {
            text = book.title,
            face = title_face,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bold = true,
        }

        local author_widget = TextWidget:new {
            text = book.author,
            face = author_face,
            fgcolor = Blitbuffer.Color8(0x40),
        }

        local spine_content = HorizontalGroup:new {
            align = "center",
            -- Progress bar (fills from top based on % read)
            FrameContainer:new {
                width = book_width,
                height = book_height,
                background = base_color,
                bordersize = 1,
                color = Blitbuffer.COLOR_BLACK,
                HorizontalSpan:new { width = progress_width },
            },
            -- Remaining space
            FrameContainer:new {
                width = book_width - progress_width,
                height = book_height,
                background = accent_color,
                bordersize = 1,
                color = Blitbuffer.COLOR_BLACK,
                HorizontalSpan:new { width = book_width - progress_width },
            }
        }

        local full_book = OverlapGroup:new {
            dimen = { w = max_width, h = book_height },
            spine_content,
            VerticalGroup:new {
                align = "left",
                VerticalSpan:new { width = Screen:scaleBySize(8) },
                HorizontalGroup:new {
                    HorizontalSpan:new { width = Screen:scaleBySize(10) },
                    title_widget,
                },
                VerticalSpan:new { width = Screen:scaleBySize(2) },
                HorizontalGroup:new {
                    HorizontalSpan:new { width = Screen:scaleBySize(10) },
                    author_widget,
                },
            },
        }

        table.insert(books_stack, full_book)

        if i < num_books then
            table.insert(books_stack,
                VerticalSpan:new { width = spacing })

            total_height = total_height + spacing
        end
    end

    local top_margin = math.max(0, screen_size.h - total_height)

    return OverlapGroup:new {
        dimen = screen_size,
        VerticalGroup:new {
            VerticalSpan:new {
                width = top_margin,
            },
            HorizontalGroup:new {
                HorizontalSpan:new { width = Screen:scaleBySize(20) },
                books_stack
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
