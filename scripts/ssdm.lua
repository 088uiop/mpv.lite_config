local mp = require 'mp'
local utils = require 'mp.utils'

local enabled = false
local auto_pad = false
local sid = nil
local key = nil
local config_dir = mp.command_native({ "expand-path", "~~/" })
local input_conf = io.open(config_dir .. '/input.conf', 'r')
local ssdm_dm_path = utils.join_path(os.getenv("TEMP"), "ssdm-danmaku-" .. utils.getpid() .. ".ass")
local uosc_danmaku_main_path = config_dir .. "/scripts/uosc_danmaku/main.lua"
local uosc_danmaku_data = { enabled = false, comments = nil, options = nil }
local updating_uosc_danmaku_data = false

if input_conf then
    for i in input_conf:lines() do
        i = i:match('^%s*(.-)%s*$')
        if i and not i:find('^#') and i ~= '' then
            if i:find('script-message show_danmaku_keyboard', 1, true) then
                key = i:match('^[%S]+') or i:match('^[%S]+%s+[%S]+')
                break
            end
        end
    end
    input_conf:close()
end

local function set_uosc_danmaku(state, callback)
    if updating_uosc_danmaku_data then
        mp.add_timeout(0.1, function() set_uosc_danmaku(state, callback) end)
        return
    end
    if uosc_danmaku_data.enabled ~= state then
        mp.command("script-message show_danmaku_keyboard")
        uosc_danmaku_data.enabled = state
    end
    if callback then callback() end
end

local function get_max_sid()
    local max_sid = 0
    for _, track in ipairs(mp.get_property_native("track-list")) do
        if track.type == "sub" and track.id > max_sid then
            max_sid = track.id
        end
    end
    return max_sid
end

local function process_danmaku(comments, output_file)
    local opt = uosc_danmaku_data.options
    if not comments or not opt then return false end
    local fout = io.open(output_file, "w")
    if not fout then return false end
    local hex = string.format("%02X", math.floor((1 - opt.opacity) * 255))
    fout:write(
        "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nTimer: 100.0000\nWrapStyle: 2\nScaledBorderAndShadow: yes\n"
    )
    fout:write(
        "\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, Strikeout, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    )
    local common_style = string.format(
        "%s,%d,&H%sFFFFFF,&H%sFFFFFF,&H%s000000,&H%s000000,%s,0,0,0,100,100,0,0,1,%s,%s",
        opt.fontname, opt.fontsize, hex, hex, hex, hex, opt.bold and "1" or "0", opt.outline, opt.shadow
    )
    fout:write(string.format("Style: R2L,%s,7,0,0,0,1\n", common_style))
    fout:write(string.format("Style: TOP,%s,8,0,0,0,1\n", common_style))
    fout:write(string.format("Style: BTM,%s,2,0,0,0,1\n", common_style))
    fout:write("\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n")
    local function format_time(seconds)
        if seconds < 0 then seconds = 0 end
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format("%d:%02d:%05.2f", h, m, s)
    end
    local display_range = opt.displayarea * 1080
    for _, event in ipairs(comments) do
        local y = 0
        if event.move then
            y = event.move[2]
        elseif event.pos then
            y = event.pos[2]
        end
        if y <= display_range then
            local duration = event.move and opt.scrolltime or opt.fixtime
            local start_time = format_time(event.start_time)
            local end_time = format_time(event.start_time + duration)
            if event.move then
                local x1, y1, x2, y2 = table.unpack(event.move)
                local new_move = string.format("move(%s,%s,%s,%s)", x1, y1, x2 * 2, y2)
                event.text = event.text:gsub("move%([^)]+%)", new_move)
            end
            fout:write(string.format("Dialogue: 0,%s,%s,%s,,0,0,0,,%s\n", start_time, end_time, event.style, event.text))
        end
    end
    fout:close()
    return true
end

local function assprocess()
    if sid then
        mp.commandv("sub-remove", sid)
        sid = nil
    end
    if AP then AP:kill() end
    if not enabled then return end
    updating_uosc_danmaku_data = true
    mp.command("script-message update_uosc_danmaku_data")
    set_uosc_danmaku(true, function()
        AP = mp.add_timeout(0.2, function()
            if mp.get_property_native("user-data/uosc_danmaku/has-danmaku") then
                local success = process_danmaku(uosc_danmaku_data.comments, ssdm_dm_path)
                if success then
                    set_uosc_danmaku(false, function()
                        mp.commandv("sub-add", ssdm_dm_path, "auto", "ssdm_danmaku")
                        sid = get_max_sid()
                        mp.set_property_number("secondary-sid", sid)
                    end)
                    return
                end
            end
            assprocess()
        end)
    end)
end

local function toggle_ssdm()
    enabled = not enabled
    mp.set_property_native("user-data/ssdm-enabled", enabled)
    mp.osd_message("弹幕形式: " .. (enabled and "次字幕" or "OSD"))
    if enabled then
        mp.set_property_native("secondary-sub-visibility", true)
        mp.add_forced_key_binding(key, "toggle_visibility", function()
            mp.command("cycle secondary-sub-visibility")
        end)
    else
        mp.set_property_native("secondary-sub-visibility", false)
        mp.remove_key_binding("toggle_visibility")
        set_uosc_danmaku(true)
    end
    assprocess()
end

local function unlock(o_aspect)
    mp.add_timeout(0.2, function()
        local w = mp.get_property_native("dwidth")
        local h = mp.get_property_native("dheight")
        if not w or not h or w * h == 0 or math.abs(w / h - o_aspect) < 0.01 then
            mp.set_property_native("auto-window-resize", true)
            Pading = false
            return
        end
        unlock(o_aspect)
    end)
end

local function smart_pad()
    if not auto_pad or Pading then return end
    local w = mp.get_property_native("dwidth")
    local h = mp.get_property_native("dheight")
    if not w or not h or w * h == 0 then return end
    local aspect = w / h
    local o_aspect = mp.get_property_native("osd-dimensions").aspect
    if math.abs(aspect - o_aspect) < 0.01 then return end
    mp.set_property_native("auto-window-resize", false)
    Pading = true
    mp.commandv("vf", "remove", "@Pad,@Format")
    mp.commandv("vf", "add", string.format("@Format:format=p010,@Pad:pad=aspect=%f:x=-1:y=-1", o_aspect))
    unlock(o_aspect)
end

local function toggle_pad()
    auto_pad = not auto_pad
    mp.set_property_native("user-data/ssdm-pad", auto_pad)
    mp.osd_message("自动填充黑边: " .. (auto_pad and "开" or "关"))
    if auto_pad then smart_pad() else mp.commandv("vf", "remove", "@Pad,@Format") end
end

local function init(_, loaded)
    if not loaded then return end
    local script = io.open(uosc_danmaku_main_path, 'a+')
    if script then
        local support = false
        for line in script:lines() do
            if line == "-- ssdm support --" then
                support = true
                break
            end
        end
        if not support then
            mp.msg.info("检测到uosc_danmaku脚本未注入ssdm支持，开始注入...")
            script:write(
                '\n-- ssdm support --\nlocal _options = options\noptions = {}\nsetmetatable(options, {\n    __index = function(_, k)\n        return _options[k]\n    end,\n    __newindex = function(_, k, v)\n        _options[k] = v\n        mp.command("script-message refresh_ssdm")\n    end\n})\nmp.register_script_message("update_uosc_danmaku_data", function()\n    local data = { enabled = ENABLED, comments = COMMENTS, options = _options }\n    mp.commandv("script-message", "uosc_danmaku_data_to_ssdm", utils.format_json(data))\nend)\n'
            )
            mp.msg.info("ssdm支持注入成功，重启后即可使用次字幕弹幕相关功能")
        end
        script:close()
    end
    if mp.get_property_native("user-data/ssdm-enabled") then
        enabled = true
        mp.add_forced_key_binding(key, "toggle_visibility", function()
            mp.command("cycle secondary-sub-visibility")
        end)
    end
    if mp.get_property_native("user-data/ssdm-pad") then
        auto_pad = true
    end
    updating_uosc_danmaku_data = true
    mp.command("script-message update_uosc_danmaku_data")
    mp.set_property_native("secondary-sub-ass-override", "yes")
    mp.observe_property("osd-dimensions", nil, smart_pad)
    mp.register_event("file-loaded", assprocess)
    mp.register_event("shutdown", function() os.remove(ssdm_dm_path) end)
    mp.register_script_message("refresh_ssdm", assprocess)
    mp.register_script_message("uosc_danmaku_data_to_ssdm", function(data)
        uosc_danmaku_data = utils.parse_json(data)
        updating_uosc_danmaku_data = false
    end)
    mp.add_key_binding(nil, "toggle_ssdm", toggle_ssdm)
    mp.add_key_binding(nil, "toggle_pad", toggle_pad)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
