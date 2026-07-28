local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local opt = {
    speed = 2,
    press_speed = false,
    clear_glsl = false,
    speed_vs_off = false,
    seek_vs_off = false,
    skip_chapters = "OP,ED,op,ed,opening,ending,Opening,Ending,オープニング,エンディング"
}

options.read_options(opt)

local function split(inputstr, sep)
    local result = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(result, str .. "$")
    end
    return result
end

local alive = false
local chap_skip = false
local chap_keywords = split(opt.skip_chapters, ",")
local original_speed = nil
local original_shaders = nil
local config_dir = mp.command_native({ "expand-path", "~~/" })

local function toggle_vs(state)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label and filter.label:find("VS") and filter.enabled ~= state then
            mp.commandv("vf", "toggle", "@" .. filter.label)
        end
    end
end

local function pause_vs()
    if Re_vs then Re_vs:kill() end
    toggle_vs(false)
end

local function restore_vs()
    if Re_vs then Re_vs:kill() end
    Re_vs = mp.add_timeout(1, function()
        if mp.get_property_native("pause") or Wait then
            restore_vs()
        else
            toggle_vs(true)
        end
    end)
end

local function chap_skip_check(_, value)
    if not value then return end
    for _, kw in ipairs(chap_keywords) do
        if string.find(value, kw) then
            mp.command("no-osd add chapter 1")
            mp.osd_message("已跳过章节: " .. value)
            break
        end
    end
end

local function chap_skip_toggle()
    chap_skip = not chap_skip
    mp.set_property_native("user-data/chap-skip", chap_skip)
    mp.osd_message("自动跳过设定章节: " .. (chap_skip and "开" or "关"))
    if chap_skip then
        mp.observe_property("chapter-metadata/TITLE", "string", chap_skip_check)
    else
        mp.unobserve_property(chap_skip_check)
    end
end

local function show_file_dialog(file_type)
    alive = true
    local res = utils.subprocess({
        args = { "openfile", file_type },
        cancellable = false
    })
    mp.add_timeout(0.125, function() alive = false end)
    return res
end

local function import(type)
    if alive then return end
    local command
    local is_replace = false
    if type == "Media" then
        command = "loadfile"
        is_replace = true
    elseif type == "AudioTrack" then
        command = "audio-add"
    elseif type == "Subtitle" then
        command = "sub-add"
    else
        return
    end
    local res = show_file_dialog(type)
    if res.status ~= 0 then return end
    local first_file = true
    for filename in string.gmatch(res.stdout, '[^\r\n]+') do
        filename = filename:gsub('^%s*(.-)%s*$', '%1')
        if filename ~= "" then
            if is_replace then
                local mode = first_file and "replace" or "append"
                mp.commandv(command, filename, mode)
                first_file = false
            else
                mp.commandv(command, filename)
            end
        end
    end
end

local function r_video()
    local current_rotate = mp.get_property_number("video-rotate", 0)
    mp.set_property("video-rotate", (current_rotate + 90) % 360)
end

local function l_video()
    local current_rotate = mp.get_property_number("video-rotate", 0)
    mp.set_property("video-rotate", (current_rotate - 90) % 360)
end

local function speed_auto(tab)
    if tab.event == "down" then
        local function start()
            original_speed = mp.get_property_number("speed")
            if opt.speed_vs_off then
                Wait = true
                pause_vs()
            end
            if opt.clear_glsl then
                original_shaders = mp.get_property_native("glsl-shaders") or nil
                mp.set_property_native("glsl-shaders", {})
            end
            mp.set_property_number("speed", original_speed * opt.speed)
        end
        if opt.press_speed then
            Press_time = mp.get_time()
            Pressed = mp.add_timeout(0.2, start)
        else
            start()
        end
    elseif tab.event == "up" then
        if opt.press_speed then
            local duration = mp.get_time() - Press_time
            if duration < 0.2 then
                mp.command("seek 3")
            end
            Press_time = nil
            if Pressed then Pressed:kill() end
        end
        if original_speed then
            mp.set_property_number("speed", original_speed)
            original_speed = nil
        end
        if original_shaders then
            mp.set_property_native("glsl-shaders", original_shaders)
            original_shaders = nil
        end
        Wait = false
        restore_vs()
    end
end

local function speed_auto_bullet(tab)
    if tab.event == "down" then
        original_speed = mp.get_property_number("speed")
        mp.set_property_number("speed", original_speed * 0.5)
    elseif tab.event == "up" then
        if original_speed then
            mp.set_property_number("speed", original_speed)
            original_speed = nil
        end
    end
end

local function track_seek(id, num)
    mp.command("add " .. id .. " " .. num)
    if mp.get_property_number(id, 0) == 0 then
        mp.command("add " .. id .. " " .. num)
        if mp.get_property_number(id, 0) == 0 then
            mp.osd_message("无可用" .. id)
        end
    end
end

local function update()
    mp.command_native({
        name = 'subprocess',
        args = { "cmd", "/c", "start", '""', "cmd", "/c", config_dir .. "/../updater.bat" },
        detach = true
    })
    mp.command_native_async({
        name = 'subprocess',
        args = { "taskkill", "/f", "/im", "mpv.exe", "/t" },
        detach = true
    })
end

local function init(_, loaded)
    if not loaded then return end
    if mp.get_property_native("user-data/chap-skip") then
        chap_skip = true
        mp.observe_property("chapter-metadata/TITLE", "string", chap_skip_check)
    end
    if opt.press_speed then
        local key = nil
        local input_conf = io.open(config_dir .. '/input.conf', 'r')
        if not input_conf then return nil end
        for i in input_conf:lines() do
            i = i:match('^%s*(.-)%s*$')
            if i and not i:find('^#') and i ~= '' then
                if i:find('seek') and not i:find('-') and not i:find("exact") then
                    key = i:match('^[%S]+') or i:match('^[%S]+%s+[%S]+')
                    break
                end
            end
        end
        input_conf:close()
        mp.add_forced_key_binding(key, "speed_auto", speed_auto, { complex = true })
    end
    if opt.seek_vs_off then
        mp.register_event("file-loaded", function() Init_seek = true end)
        mp.observe_property("seeking", "bool", function(_, seeking)
            if Init_seek then
                Init_seek = false
                return
            end
            if seeking then
                pause_vs()
            else
                restore_vs()
            end
        end)
    end
    mp.add_key_binding(nil, "chap_skip_toggle", chap_skip_toggle)
    mp.add_key_binding(nil, "import_files", function() import("Media") end)
    mp.add_key_binding(nil, "import_append_aid", function() import("AudioTrack") end)
    mp.add_key_binding(nil, "import_append_sid", function() import("Subtitle") end)
    mp.add_key_binding(nil, "speed_auto", speed_auto, { complex = true })
    mp.add_key_binding(nil, "speed_auto_bullet", speed_auto_bullet, { complex = true })
    mp.add_key_binding(nil, "trackA_back", function() track_seek("aid", -1) end)
    mp.add_key_binding(nil, "trackA_next", function() track_seek("aid", 1) end)
    mp.add_key_binding(nil, "trackS_back", function() track_seek("sid", -1) end)
    mp.add_key_binding(nil, "trackS_next", function() track_seek("sid", 1) end)
    mp.add_key_binding(nil, "r_video", r_video)
    mp.add_key_binding(nil, "l_video", l_video)
    mp.add_key_binding(nil, "update", update)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
