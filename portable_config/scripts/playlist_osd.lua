local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'
local assdraw = require 'mp.assdraw'

-- ========== 配置 ==========
local settings = {
    key_move2up = "UP",
    key_move2down = "DOWN",
    key_move2pageup = "PGUP",
    key_move2pagedown = "PGDWN",
    key_move2begin = "HOME",
    key_move2end = "END",
    key_file_select = "RIGHT",
    key_file_unselect = "LEFT",
    key_file_play = "ENTER",
    key_file_remove = "BS",
    key_playlist_close = "ESC",

    show_title_on_file_load = false,
    show_playlist_on_file_load = false,
    close_playlist_on_playfile = false,
    sync_cursor_on_load = true,
    loop_cursor = true,
    reset_cursor_on_open = true,
    playlist_display_timeout = 0,
    showamount = 12,
    slice_longfilenames = false,
    slice_longfilenames_amount = 80,

    style_ass_tags = "{\\rDefault\\an7\\fs24\\b0\\blur0\\bord1\\1c&HFFFFFF\\3c&H000000\\q2}",
    playlist_header = "{\\b1\\fs30}Play List [%cursor/%plen]{\\b0\\fs24}",
    normal_file = "{\\1c&HCCCCCC&}• %name",
    hovered_file = "{\\1c&HFFFFFF&}> %name",
    selected_file = "{\\1c&HFFD700&}* %name",
    playing_file = "{\\1c&H00FF00&}▶ %name",
    playing_hovered_file = "{\\1c&H00FF00&}▶> %name",
    playing_selected_file = "{\\1c&HFFD700&}*▶ %name",
    playlist_sliced_prefix = "{\\1c&HFF0000&}▲",
    playlist_sliced_suffix = "{\\1c&HFF0000&}▼",
}

options.read_options(settings)

-- ========== 状态 ==========
local selection = nil
local playlist_overlay = mp.create_osd_overlay("ass-events")
local playlist_visible = false
local strippedname = nil
local path = nil
local pos = 0
local plen = 0
local cursor = 0
local title_table = {}
local keybindstimer = nil

-- ========== 工具函数 ==========
local function refresh_globals()
    pos = mp.get_property_number("playlist-pos", 0)
    plen = mp.get_property_number("playlist-count", 0)
end

local function is_protocol(p)
    return type(p) == "string" and p:match("^%a[%a%d-_]+://") ~= nil
end

local function stripfilename(p)
    if not p then return "" end
    if settings.slice_longfilenames and #p > settings.slice_longfilenames_amount + 5 then
        p = p:sub(1, settings.slice_longfilenames_amount):gsub(".[\128-\191]*$", "") .. " ..."
    end
    return p
end

local function get_name_from_index(i)
    refresh_globals()
    if plen <= i then return nil end
    local title = mp.get_property("playlist/" .. i .. "/title")
    local name = mp.get_property("playlist/" .. i .. "/filename")
    if not title and title_table[name] then title = title_table[name] end
    if not title then
        if string.sub(name, 1, 1) == "/" or name:match("^%a:[/\\]") then
            _, name = utils.split_path(name)
        end
        title = name
    end
    return stripfilename(title):gsub("\\", "\\\239\187\191"):gsub("{", "\\{"):gsub("^ ", "\\h")
end

local function parse_header(str)
    local esc_title = stripfilename(mp.get_property("media-title") or ""):gsub("%%", "%%%%")
    local esc_file = stripfilename(mp.get_property("filename") or ""):gsub("%%", "%%%%")
    return str:gsub("%%N", "\\N")
        :gsub("%%pos", mp.get_property_number("playlist-pos", 0) + 1)
        :gsub("%%plen", mp.get_property("playlist-count"))
        :gsub("%%cursor", cursor + 1)
        :gsub("%%mediatitle", esc_title)
        :gsub("%%filename", esc_file)
        :gsub("%%%%", "%%")
end

local function parse_filename(str, name)
    local esc_name = stripfilename(name or "")
    return str
        :gsub("%%N", "\\N")
        :gsub("%%pos", mp.get_property_number("playlist-pos", 0) + 1)
        :gsub("%%name", esc_name)
        :gsub("%%%%", "%%")
end

local function parse_filename_by_index(index)
    local template = settings.normal_file
    local is_idle = mp.get_property_native("idle-active")
    if index == (is_idle and -1 or pos) then
        template = (index == cursor and (selection and settings.playing_selected_file or settings.playing_hovered_file))
            or settings.playing_file
    elseif index == cursor then
        template = selection and settings.selected_file or settings.hovered_file
    end
    return parse_filename(template, get_name_from_index(index))
end

local function is_terminal_mode()
    local w, h, ar = mp.get_osd_size()
    return w == 0 and h == 0 and ar == 0
end

local function split_keys(keys)
    local out = {}
    if not keys then return out end
    for k in keys:gmatch("[^%s]+") do
        table.insert(out, k)
    end
    return out
end

local function add_forced_key_bindings(key, name, func, opt)
    for i, k in ipairs(split_keys(key)) do
        local suffix = (i == 1) and "" or tostring(i)
        mp.add_forced_key_binding(k, name .. suffix, func, opt)
    end
end

local function remove_forced_key_bindings(keys, name)
    for i, _ in ipairs(split_keys(keys)) do
        local suffix = (i == 1) and "" or tostring(i)
        pcall(mp.remove_key_binding, name .. suffix)
    end
end

local function remove_keybinds()
    if keybindstimer then keybindstimer:kill() end
    playlist_overlay.data = ""
    playlist_overlay:remove()
    playlist_visible = false
    remove_forced_key_bindings(settings.key_move2up, "moveup")
    remove_forced_key_bindings(settings.key_move2down, "movedown")
    remove_forced_key_bindings(settings.key_move2pageup, "movepageup")
    remove_forced_key_bindings(settings.key_move2pagedown, "movepagedown")
    remove_forced_key_bindings(settings.key_move2begin, "movebegin")
    remove_forced_key_bindings(settings.key_move2end, "moveend")
    remove_forced_key_bindings(settings.key_file_select, "selectfile")
    remove_forced_key_bindings(settings.key_file_unselect, "unselectfile")
    remove_forced_key_bindings(settings.key_file_play, "playfile")
    remove_forced_key_bindings(settings.key_file_remove, "removefile")
    remove_forced_key_bindings(settings.key_playlist_close, "closeplaylist")
end

local function refresh_keybind_timer()
    if keybindstimer then keybindstimer:kill() end
    local dur = tonumber(settings.playlist_display_timeout) or 0
    if dur > 0 then
        keybindstimer = mp.add_periodic_timer(dur, remove_keybinds)
    end
end

-- ========== 绘制 ==========
local function draw_playlist()
    refresh_globals()
    if cursor == -1 then cursor = 0 end
    local page_size = settings.showamount
    local page_start = math.floor(cursor / page_size) * page_size
    local page_end = math.min(page_start + page_size - 1, plen - 1)

    local ass = assdraw.ass_new()
    local terminaloutput = ""
    ass:append(settings.style_ass_tags)

    if settings.playlist_header ~= "" then
        local header = parse_header(settings.playlist_header)
        ass:append(header .. "\\N")
        terminaloutput = terminaloutput .. header .. "\n"
    end

    if page_start > 0 then
        ass:append(settings.playlist_sliced_prefix .. "\\N")
        terminaloutput = terminaloutput .. settings.playlist_sliced_prefix .. "\n"
    end

    for i = page_start, page_end do
        local fname = parse_filename_by_index(i)
        ass:append(fname .. "\\N")
        terminaloutput = terminaloutput .. fname .. "\n"
    end

    if page_end < plen - 1 then
        ass:append(settings.playlist_sliced_suffix .. "\\N")
        terminaloutput = terminaloutput .. settings.playlist_sliced_suffix .. "\n"
    end

    if is_terminal_mode() then
        mp.osd_message(terminaloutput,
            settings.playlist_display_timeout == 0 and 2147483 or settings.playlist_display_timeout)
    else
        playlist_overlay.data = ass.text
        playlist_overlay:update()
    end
end

-- ========== 控制 ==========
local function resetcursor()
    selection = nil
    cursor = mp.get_property_number("playlist-pos", 0)
end

local function playlist_show(duration)
    refresh_globals()
    if plen == 0 then return end
    if not playlist_visible and settings.reset_cursor_on_open then resetcursor() end
    playlist_visible = true

    local function handle_movement(target)
        local final_target = math.max(0, math.min(plen - 1, target))
        if selection then
            local dest = final_target
            if final_target > selection then
                dest = final_target + 1
            end
            mp.commandv("playlist-move", selection, dest)
            selection = final_target
        end

        cursor = final_target
        draw_playlist()
        refresh_keybind_timer()
    end

    add_forced_key_bindings(settings.key_move2up, "moveup", function()
        refresh_globals()
        if plen == 0 then return end
        local target = cursor - 1
        if target < 0 then
            if settings.loop_cursor and not selection then target = plen - 1 else return end
        end
        handle_movement(target)
    end, "repeatable")

    add_forced_key_bindings(settings.key_move2down, "movedown", function()
        refresh_globals()
        if plen == 0 then return end

        local target = cursor + 1
        if target >= plen then
            if settings.loop_cursor and not selection then target = 0 else return end
        end
        handle_movement(target)
    end, "repeatable")

    add_forced_key_bindings(settings.key_move2pageup, "movepageup", function()
        refresh_globals()
        if plen == 0 or cursor == 0 then return end
        handle_movement(math.max(0, cursor - settings.showamount))
    end, "repeatable")

    add_forced_key_bindings(settings.key_move2pagedown, "movepagedown", function()
        refresh_globals()
        if plen == 0 or cursor == plen - 1 then return end
        handle_movement(math.min(plen - 1, cursor + settings.showamount))
    end, "repeatable")

    add_forced_key_bindings(settings.key_move2begin, "movebegin", function()
        refresh_globals()
        if plen == 0 or cursor == 0 then return end
        handle_movement(0)
    end, "repeatable")

    add_forced_key_bindings(settings.key_move2end, "moveend", function()
        refresh_globals()
        if plen == 0 or cursor == plen - 1 then return end
        handle_movement(plen - 1)
    end, "repeatable")

    add_forced_key_bindings(settings.key_file_select, "selectfile", function()
        refresh_globals()
        if plen == 0 then return end
        selection = selection and nil or cursor
        draw_playlist()
        refresh_keybind_timer()
    end)

    add_forced_key_bindings(settings.key_file_unselect, "unselectfile", function()
        selection = nil
        draw_playlist()
        refresh_keybind_timer()
    end)

    add_forced_key_bindings(settings.key_file_play, "playfile", function()
        refresh_globals()
        if plen == 0 then return end
        mp.set_property("playlist-pos", cursor)
        if settings.close_playlist_on_playfile then remove_keybinds() end
    end)

    add_forced_key_bindings(settings.key_file_remove, "removefile", function()
        refresh_globals()
        if plen == 0 then return end
        if selection and selection == cursor then selection = nil end
        mp.commandv("playlist-remove", cursor)
        refresh_globals()
        if cursor >= plen then cursor = math.max(0, plen - 1) end
        if plen == 0 then remove_keybinds() else draw_playlist() end
        refresh_keybind_timer()
    end, "repeatable")

    add_forced_key_bindings(settings.key_playlist_close, "closeplaylist", remove_keybinds)
    draw_playlist()
    if keybindstimer then keybindstimer:kill() end
    local dur = tonumber(duration) or settings.playlist_display_timeout
    if dur > 0 then keybindstimer = mp.add_periodic_timer(dur, remove_keybinds) end
end

-- ========== 事件 ==========
local function on_file_loaded()
    refresh_globals()
    path = mp.get_property("path")
    local media_title = mp.get_property("media-title")
    if is_protocol(path) and not title_table[path] and path ~= media_title then
        title_table[path] = media_title
    end
    if settings.sync_cursor_on_load then
        cursor = pos; if playlist_visible then draw_playlist() end
    end
    strippedname = stripfilename(media_title)
    if settings.show_title_on_file_load then mp.commandv("show-text", strippedname) end
    if settings.show_playlist_on_file_load then playlist_show() end
end

local function on_end_file()
    strippedname, path = nil, nil
    if playlist_visible then playlist_show() end
end

-- ========== 注册 ==========
mp.register_script_message("playlist_osd", function(msg, value, value2)
    if msg == "show" and value == "playlist" then
        if value2 ~= "toggle" then
            playlist_show(value2)
        else
            if playlist_visible then
                remove_keybinds()
            else
                playlist_show()
            end
        end
    elseif msg == "close" then
        remove_keybinds()
    end
end)

mp.register_event("file-loaded", on_file_loaded)
mp.register_event("end-file", on_end_file)
mp.add_key_binding(nil, "display", playlist_show)
