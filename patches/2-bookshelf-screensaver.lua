local Device = require("device")
local Blitbuffer = require("ffi/blitbuffer")
local UIManager = require("ui/uimanager")
local ScreenSaverWidget = require("ui/widget/screensaverwidget")
local Font = require("ui/font")
local TextWidget = require("ui/widget/textwidget")
local ImageWidget = require("ui/widget/imagewidget")
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
            (SELECT page FROM page_stat WHERE id_book = b.id ORDER BY start_time DESC LIMIT 1) as current_page,
            b.total_read_time, b.total_read_pages, b.md5
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
        local total_read_time = tonumber(results[6][i]) or 0
        local total_read_pages = tonumber(results[7][i]) or 0
        -- Calculate time remaining
        local time_remaining = nil
        if total_read_pages > 0 and current_page < pages then
            local avg_time_per_page = total_read_time / total_read_pages
            local pages_remaining = pages - current_page
            time_remaining = math.floor(avg_time_per_page * pages_remaining)
        end

        print(string.format("DEBUG: Found book - %s by %s (%d/%d pages, time %s)",
            title, author, current_page, pages, tostring(time_remaining or "N/A")))

        -- Calculate progress percentage
        local progress = math.floor((current_page / pages) * 100)
        if progress > 100 then progress = 100 end
        if progress < 0 then progress = 0 end

        table.insert(books, {
            title = title,
            author = author,
            pages = pages,
            progress = progress,
            time_remaining = time_remaining,
        })
    end

    print("DEBUG: Found " .. #books .. " books")

    if #books == 0 then
        print("DEBUG: No books in result")
        return nil
    end

    return books
end

local function formatTimeRemaining(seconds)
    if not seconds or seconds <= 0 then
        return nil
    end
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

local function createDottedBackground()
    local screen_size = Screen:getSize()
    local bb = Blitbuffer.new(screen_size.w, screen_size.h, Blitbuffer.TYPE_BB8)

    bb:fill(Blitbuffer.Color8(0xF5)) -- Light base

    local dot_spacing = Screen:scaleBySize(25)
    local dot_size = Screen:scaleBySize(2)
    for y = dot_spacing, screen_size.h - 1, dot_spacing do
        for x = dot_spacing, screen_size.w - 1, dot_spacing do
            bb:paintRect(x, y, dot_size, dot_size, Blitbuffer.Color8(0xD0))
        end
    end

    return ImageWidget:new {
        image = bb,
        width = screen_size.w,
        height = screen_size.h,
    }
end

local function isColorScreen()
    return Screen:isColorEnabled() or Screen:isColorScreen()
end

local function getBookColor(index, getRandom)
    if isColorScreen() then
        local colors = {
            Blitbuffer.ColorRGB32(220, 120, 120, 255), -- Light red
            Blitbuffer.ColorRGB32(120, 190, 120, 255), -- Light green
            Blitbuffer.ColorRGB32(130, 160, 220, 255), -- Light blue
        }
        if getRandom then
            return colors[math.random(1, #colors)]
        else
            return colors[((index - 1) % #colors) + 1]
        end
    else
        local shades = {
            Blitbuffer.Color8(0xA0),
            Blitbuffer.Color8(0x80),
            Blitbuffer.Color8(0xB0),
            Blitbuffer.Color8(0x90),
        }
        if getRandom then
            return shades[math.random(1, #shades)]
        else
            return shades[((index - 1) % #shades) + 1]
        end
    end
end

local function getShadowColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(80, 80, 80, 255)
    else
        return Blitbuffer.Color8(0x40)
    end
end

local function getBandColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(230, 190, 50, 255) -- Yellow/gold
    else
        return Blitbuffer.Color8(0xF0)
    end
end

local function getAccentColor()
    if isColorScreen() then
        return Blitbuffer.ColorRGB32(240, 235, 220, 255) -- Warm cream
    else
        return Blitbuffer.Color8(0xE0)
    end
end

local function considerBookComplete(progress, assume)
    return progress >= assume
end


local function buildBookshelfWidget()
    local screen_size = Screen:getSize()
    local show_background = true
    local show_cat = true
    local show_time_remaining = true
    local show_percent_completed = true
    local show_book_bands = true
    local use_random_colors = false
    local assume_finished_at_percent = 97

    print("DEBUG: Screen DPI = " .. tostring(Screen:getDPI()))
    print("DEBUG: Screen size = " .. screen_size.w .. "x" .. screen_size.h)

    local books = getRecentBooks(5)

    -- if not books then
    --     -- Fake book data as fallback/if no data yet
    -- books = {
    --     { title = "1984",                                    author = "George Orwell",     pages = 180,  progress = 89, time_remaining = 24729 },
    --     { title = "Mistborn: Final Empire",                  author = "Brandon Sanderson", pages = 600,  progress = 98, time_remaining = 6552 },
    --     { title = "Neuromancer",                             author = "William Gibson",    pages = 200,  progress = 45, time_remaining = 8966 },
    --     { title = "Whispers of Scarlet and Midnight Blooms", author = "SakakiHaruna12",    pages = 1200, progress = 67, time_remaining = 22751 },
    --     { title = "Dune",                                    author = "Frank Herbert",     pages = 1000, progress = 23, time_remaining = 13340 },
    -- }
    -- end

    local num_books = #books
    local books_stack = VerticalGroup:new {
        align = "left",
    }

    local top_width = screen_size.w
    local max_width = 0
    local total_height = 0

    local spacing = Screen:scaleBySize(3)
    local shadow_size = Screen:scaleBySize(2)
    local shadow_color = getShadowColor()
    local band_color = getBandColor()

    for i = 1, num_books do
        local book = books[i]
        local left_offset = Screen:scaleBySize(math.random(0, 15))

        -- Small book 200 (thin), Large book 1000 (thick)
        local page_count = book.pages or 300
        local normalized_page_count = math.min(math.max(page_count, 200), 1000)

        -- book thickness
        local height_factor = (normalized_page_count - 200) / (1000 - 200)
        local book_height = math.floor(screen_size.h * (0.08 + (height_factor * 0.05)))

        -- book length
        local width_factor = (normalized_page_count - 200) / (1000 - 200)
        local width_percent = 0.60 + (width_factor * 0.25) -- [60-85]%
        local book_width = math.floor(screen_size.w * width_percent)

        if i == 1 then
            top_width = book_width
        end
        max_width = math.max(max_width, book_width)
        total_height = total_height + book_height + shadow_size + shadow_size

        local band_size = Screen:scaleBySize(5 + math.floor(3 * height_factor))

        local base_color = getBookColor(i, use_random_colors)
        local accent_color = getAccentColor()

        local progress = book.progress or 0
        local progress_width = math.floor(book_width * (progress / 100))

        local title_face = Font:getFace("cfont", Screen:scaleBySize(6 + math.floor(height_factor * 3)))
        local author_face = Font:getFace("cfont", Screen:scaleBySize(5 + math.floor(height_factor * 2)))

        local title_widget = TextWidget:new {
            text = book.title,
            face = title_face,
            fgcolor = Blitbuffer.COLOR_BLACK,
            bold = true,
            max_width = 0.8 * book_width,
        }

        local author_text = book.author
        if show_percent_completed and not considerBookComplete(progress, assume_finished_at_percent) then
            author_text = progress .. "% • " .. author_text
        end
        if show_time_remaining and (not considerBookComplete(progress, assume_finished_at_percent)) and book.time_remaining then -- toggle via setting
            author_text = formatTimeRemaining(book.time_remaining) .. " • " .. author_text
        end
        local author_widget = TextWidget:new {
            text = author_text,
            face = author_face,
            fgcolor = Blitbuffer.Color8(0x40),
            max_width = 0.7 * book_width,
        }

        local spine = nil
        if considerBookComplete(progress, assume_finished_at_percent) then
            spine = HorizontalGroup:new {
                FrameContainer:new {
                    width = book_width,
                    height = book_height,
                    background = base_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width },
                },
            }
        else
            spine = HorizontalGroup:new {
                -- Progress bar (fills from left based on % read)
                FrameContainer:new {
                    width = progress_width,
                    height = book_height,
                    background = base_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = progress_width },
                },
                FrameContainer:new {
                    width = book_width - progress_width,
                    height = book_height,
                    background = accent_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width - progress_width },
                }
            }
        end

        spine = FrameContainer:new {
            width = book_width,
            height = book_height,
            bordersize = 1,
            color = Blitbuffer.COLOR_BLACK,
            padding = 0,
            spine,
        }

        spine = OverlapGroup:new {
            dimen = { w = book_width + shadow_size + 2, h = book_height + shadow_size + 2 },
            spine,
            -- Right shadow
            HorizontalGroup:new {
                HorizontalSpan:new { width = book_width },
                FrameContainer:new {
                    width = shadow_size + 5,
                    height = book_height + 5,
                    background = shadow_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_width + 5 },
                },
            },
            -- Bottom shadow
            VerticalGroup:new {
                VerticalSpan:new { width = book_height },
                FrameContainer:new {
                    width = book_width + shadow_size + 2,
                    height = shadow_size,
                    background = shadow_color,
                    bordersize = 0,
                    padding = 0,
                    HorizontalSpan:new { width = book_height + 2 },
                },
            },
        }
        if show_book_bands then
            local left_band_loc = math.floor(book_width * 0.05)
            spine = OverlapGroup:new {
                dimen = { w = book_width, h = book_height },
                spine,
                -- Vertical left band
                HorizontalGroup:new {
                    HorizontalSpan:new { width = left_band_loc },
                    FrameContainer:new {
                        width = band_size,
                        height = book_height,
                        background = band_color,
                        bordersize = 1,
                        color = Blitbuffer.COLOR_BLACK,
                        padding = 0,
                        HorizontalSpan:new { width = book_width },
                    },
                }
            }

            if considerBookComplete(progress, assume_finished_at_percent) then
                spine = OverlapGroup:new {
                    dimen = { w = book_width, h = book_height },
                    spine,
                    -- Vertical left band
                    HorizontalGroup:new {
                        HorizontalSpan:new { width = book_width - left_band_loc - band_size },
                        FrameContainer:new {
                            width = band_size,
                            height = book_height,
                            background = band_color,
                            bordersize = 1,
                            color = Blitbuffer.COLOR_BLACK,
                            padding = 0,
                            HorizontalSpan:new { width = book_width },
                        },
                    }
                }
            end
        end

        local book_spine = OverlapGroup:new {
            dimen = { w = max_width, h = book_height + shadow_size },
            spine,
            HorizontalGroup:new {
                align = "center",
                HorizontalSpan:new { width = (book_width / 2) - (math.max(title_widget:getSize().w, author_widget:getSize().w) / 2) },
                VerticalGroup:new {
                    align = "center",
                    VerticalSpan:new { width = (book_height - title_widget:getSize().h - author_widget:getSize().h) / 2 },
                    title_widget,
                    author_widget
                }
            }
        }

        table.insert(books_stack, HorizontalGroup:new {
            HorizontalSpan:new { width = left_offset },
            book_spine,
        })

        if i < num_books then
            table.insert(books_stack,
                VerticalSpan:new { width = spacing })

            total_height = total_height + spacing
        end
    end

    local top_margin = math.max(0, screen_size.h - total_height)

    local main_stack = VerticalGroup:new {
        VerticalSpan:new {
            width = top_margin - Screen:scaleBySize(20),
        },
        HorizontalGroup:new {
            HorizontalSpan:new { width = Screen:scaleBySize(20) },
            books_stack
        },
    }

    local cat_widget = nil
    local cat_path = DataStorage:getDataDir() .. "/patches/cat.png"
    local cat_size = Screen:scaleBySize(200)
    local cat_attrs = lfs.attributes(cat_path, "mode")
    if cat_attrs == "file" then
        cat_widget = ImageWidget:new {
            file = cat_path,
            width = Screen:scaleBySize(200),
            height = Screen:scaleBySize(200),
            alpha = true,
        }
    end

    -- At the end, layer it:
    local final_widget = OverlapGroup:new {
        dimen = screen_size,
    }

    -- Add background first (bottom layer)
    if show_background then
        local bg_widget = createDottedBackground()

        table.insert(final_widget, bg_widget)
    end

    -- Add your content on top
    table.insert(final_widget, main_stack)

    -- Add cat on top of everything
    if show_cat and cat_widget then
        table.insert(final_widget, VerticalGroup:new {
            -- ... cat positioning ...
            VerticalSpan:new {
                width = top_margin - cat_size + Screen:scaleBySize(10),
            },
            HorizontalGroup:new {
                HorizontalSpan:new { width = top_width - cat_size + Screen:scaleBySize(20) },
                cat_widget,
            },
        })
    end

    return final_widget
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
