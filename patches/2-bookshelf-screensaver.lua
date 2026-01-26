local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local DataStorage = require("datastorage")
local SQ3 = require("lua-ljsqlite3/init")
local lfs = require("libs/libkoreader-lfs")

local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local VerticalGroup = require("ui/widget/verticalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local VerticalSpan = require("ui/widget/verticalspan")
local OverlapGroup = require("ui/widget/overlapgroup")

local Screen = Device.screen

local STATISTICS_DB_PATH = DataStorage:getSettingsDir() .. "/statistics.sqlite3"

local function getRecentBooks(max_books)
    if not STATISTICS_DB_PATH or STATISTICS_DB_PATH == "" then
        print("DEBUG: No database path")
        return nil
    end

    local attrs = lfs.attributes(STATISTICS_DB_PATH, "mode")
    if attrs ~= "file" then
        print("DEBUG: Database file not found at: " .. STATISTICS_DB_PATH)
        return nil
    end

    local ok_conn, conn = pcall(SQ3.open, STATISTICS_DB_PATH)
    if not ok_conn or not conn then
        print("DEBUG: Failed to open database: " .. tostring(conn))
        return nil
    end

    -- Query for recent books
    local sql_stmt = string.format([[
        SELECT b.title, b.authors, b.pages, MAX(p.start_time) as last_read,
               (SELECT page FROM page_stat WHERE id_book = b.id ORDER BY start_time DESC LIMIT 1) as current_page
        FROM book b
        LEFT JOIN page_stat p ON b.id = p.id_book
        GROUP BY b.id
        ORDER BY last_read DESC
        LIMIT %d;
    ]], max_books)

    local books = {}
    local ok_query, results = pcall(function()
        return conn:exec(sql_stmt)
    end)

    conn:close()

    if not ok_query then
        print("DEBUG: Query failed: " .. tostring(results))
        return nil
    end

    if not results or not results[1] then
        print("DEBUG: No results from query")
        return nil
    end

    -- Results are by column: results[1] is title column, results[2] is authors, etc.
    local num_rows = #results[1]

    for i = 1, num_rows do
        local title = results[1][i] or "Unknown"
        local author = results[2][i] or "Unknown Author"
        local pages = tonumber(results[3][i]) or 200
        local current_page = tonumber(results[5][i]) or 1

        print(string.format("DEBUG: Found book - %s by %s (%d/%d pages)",
            title, author, current_page, pages))

        -- Calculate progress percentage
        local progress = math.floor((current_page / pages) * 100)
        if progress > 100 then progress = 100 end
        if progress < 0 then progress = 0 end

        table.insert(books, {
            title = title,
            author = author,
            pages = pages,
            progress = progress,
        })
    end

    print("DEBUG: Found " .. #books .. " books")

    if #books == 0 then
        print("DEBUG: No books in result")
        return nil
    end

    return books
end

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

    local books = getRecentBooks(5)

    if not books then
        -- Fake book data as fallback/if no data yet
        books = {
            { title = "Neuromancer", author = "William Gibson", pages = 200,  progress = 45 },
            { title = "Foundation",  author = "Isaac Asimov",   pages = 1200, progress = 67 },
            { title = "Dune",        author = "Frank Herbert",  pages = 1000, progress = 23 },
            { title = "1984",        author = "George Orwell",  pages = 300,  progress = 89 },
            { title = "The Hobbit",  author = "J.R.R. Tolkien", pages = 650,  progress = 12 },
        }
    end

    local num_books = 5
    local books_stack = VerticalGroup:new {
        align = "left",
    }

    local max_width = 0
    local total_height = 0
    local spacing = Screen:scaleBySize(3)

    for i = 1, num_books do
        local book = books[i]

        -- Small book 200 (thin), Large book 1000 (thick)
        local page_count = book.pages or 300
        local normalized_page_count = math.min(math.max(page_count, 200), 1000)

        -- book thickness
        local height_factor = (normalized_page_count - 200) / (1000 - 200)
        local book_height = Screen:scaleBySize(50 + (height_factor * 70))

        -- book length
        local width_factor = (normalized_page_count - 200) / (1000 - 200)
        local width_percent = 0.60 + (width_factor * 0.25) -- [60-85]%
        local book_width = math.floor(screen_size.w * width_percent)

        max_width = math.max(max_width, book_width)
        total_height = total_height + book_height

        local base_color = getBookColor(i)
        local accent_color = Blitbuffer.Color8(math.min(0xFF, base_color.a + 0x50))

        local progress = book.progress or 0
        local progress_width = math.floor(book_width * (progress / 100))

        local title_face = Font:getFace("cfont", Screen:scaleBySize(10 + math.floor(height_factor * 2)))
        local author_face = Font:getFace("cfont", Screen:scaleBySize(7 + math.floor(height_factor * 2)))

        local title_widget = TextWidget:new {
            text = book.title,
            face = title_face,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bold = true,
            max_width = book_width - Screen:scaleBySize(20),
        }

        local author_widget = TextWidget:new {
            text = book.author,
            face = author_face,
            fgcolor = Blitbuffer.Color8(0x40),
            max_width = book_width - Screen:scaleBySize(20),
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
                width = top_margin - Screen:scaleBySize(20),
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
