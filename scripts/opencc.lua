local mp = require 'mp'
local utils = require 'mp.utils'

local state = 0
local original_sid = nil
local converted_sid = nil
local config_dir = mp.command_native({ "expand-path", "~~/" })

local function get_sub_spec(track)
    local codec = (track.codec or ""):lower()
    local is_ass = codec:find("ass") or codec:find("ssa")
    return {
        ext = is_ass and ".ass" or ".srt",
        codec = is_ass and "copy" or "srt",
        is_ass = is_ass
    }
end

local function split_ass_dialogue(line)
    local pos = 1
    for _ = 1, 9 do
        local next = line:find(",", pos)
        if not next then return line, "" end
        pos = next + 1
    end
    return line:sub(1, pos - 1), line:sub(pos)
end

local function process_sub(is_ass, in_path, out_path, config_path, callback)
    if not is_ass then
        mp.command_native_async({
            name = 'subprocess',
            args = { "opencc", "-i", in_path, "-o", out_path, "-c", config_path }
        }, function() callback() end)
        return
    end
    local f_in = io.open(in_path, "r")
    if not f_in then return end
    local lines, texts_to_convert = {}, {}
    for line in f_in:lines() do
        line = line:gsub("[\r\n]", "")
        if line:match("^Dialogue:") then
            local prefix, text = split_ass_dialogue(line)
            table.insert(lines, { type = "dialogue", prefix = prefix })
            table.insert(texts_to_convert, text)
        else
            table.insert(lines, { type = "raw", text = line })
        end
    end
    f_in:close()
    local tmp_txt = os.tmpname() .. ".txt"
    local f_tmp = io.open(tmp_txt, "w")
    if f_tmp then
        f_tmp:write(table.concat(texts_to_convert, "\n"))
        f_tmp:close()
    end
    mp.command_native_async({
        name = 'subprocess',
        args = { "opencc", "-i", tmp_txt, "-o", tmp_txt, "-c", config_path }
    }, function()
        local f_txt = io.open(tmp_txt, "r")
        local f_out = io.open(out_path, "w")
        if f_txt and f_out then
            for _, l in ipairs(lines) do
                if l.type == "dialogue" then
                    local c_text = f_txt:read("*l") or ""
                    f_out:write(l.prefix .. c_text .. "\n")
                else
                    f_out:write(l.text .. "\n")
                end
            end
            f_txt:close()
            f_out:close()
        end
        os.remove(tmp_txt)
        callback()
    end)
end

local function load_converted_sub(path)
    mp.commandv("sub-add", path, "select", "opencc")
    local tracks = mp.get_property_native("track-list")
    for _, t in ipairs(tracks) do
        if t.type == "sub" and t.title == "opencc" then
            converted_sid = t.id
            break
        end
    end
end

local function convert_subtitles(sid)
    if state == 0 or not sid then return end
    original_sid = sid
    local track = nil
    for _, t in ipairs(mp.get_property_native("track-list")) do
        if t.type == "sub" and t.id == tonumber(sid) then
            track = t
            break
        end
    end
    if not track or track.title == "opencc" then return end
    local spec = get_sub_spec(track)
    local video_path = mp.get_property("path")
    local tmp_src = os.tmpname() .. spec.ext
    local args = track.external and
        { "ffmpeg", "-y", "-i", track["external-filename"], "-c:s", spec.codec, tmp_src } or
        { "ffmpeg", "-y", "-i", video_path, "-map", "0:" .. track["ff-index"], "-c:s", spec.codec, tmp_src }
    mp.command_native_async({
        name = 'subprocess',
        args = args
    }, function()
        local opencc_conf = config_dir .. "/../" .. (state == 1 and "t2s.json" or "s2t.json")
        local out_path = utils.join_path(os.getenv("TEMP"), "opencc-sub" .. utils.getpid() .. spec.ext)
        process_sub(spec.is_ass, tmp_src, out_path, opencc_conf, function()
            os.remove(tmp_src)
            load_converted_sub(out_path)
            mp.register_event("shutdown", function() os.remove(out_path) end)
        end)
    end)
end

local function set_convert_mode(mode)
    state = mode
    mp.set_property_native("user-data/opencc-mode", state)
    mp.command("script-message save_state")
    if converted_sid then
        mp.commandv("sub-remove", converted_sid)
        converted_sid = nil
        mp.set_property("sid", original_sid or "auto")
    end
    convert_subtitles(mp.get_property_number("sid"))
    local status_msg = ({ [0] = "关闭", [1] = "繁转简", [2] = "简转繁" })[state]
    mp.osd_message("字幕繁简转换: " .. status_msg)
end

local function init(_, loaded)
    if not loaded then return end
    local saved = mp.get_property_native("user-data/opencc-mode")
    if saved then
        state = saved
    else
        mp.set_property_native("user-data/opencc-mode", state)
    end
    convert_subtitles(mp.get_property_number("sid"))
    mp.register_event("file-loaded", function() convert_subtitles(mp.get_property_number("sid")) end)
    mp.register_script_message("opencc_set", function(v) set_convert_mode(tonumber(v)) end)
    mp.add_key_binding(nil, "toggle-state", function() set_convert_mode((state + 1) % 3) end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
