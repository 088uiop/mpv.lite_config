local mp = require 'mp'
local utils = require 'mp.utils'

local form = "osd"
local sid = nil
local overlay_pipe = nil
local overlay_started = false
local overlay_connected = false
local overlay_hdr = false
local pad = false
local ass_loaded = false
local show_danmaku = false
local danmaku_loaded = false
local danmaku_delay = 0
local overlay_peak = "sdr"
local pid = utils.getpid()
local pipe_full = string.format("//./pipe/danmaku_overlay_%d", pid)
local ass_path = os.getenv("TEMP") .. "/ssdm-danmaku-" .. pid .. ".ass"

local function overlay_connect()
    if overlay_connected then return true end
    local pipe = io.open(pipe_full, "wb")
    if not pipe then return false end
    pipe:setvbuf("no")
    overlay_pipe = pipe
    overlay_connected = true
    return true
end

local function overlay_disconnect()
    if overlay_pipe then pcall(function() overlay_pipe:close() end) end
    overlay_pipe = nil
    overlay_connected = false
end

local function overlay_send(json)
    if not overlay_connected or not overlay_pipe then return false end
    local data = json .. "\n"
    local ok = overlay_pipe:write(data)
    if not ok then
        overlay_disconnect()
        return false
    end
    local fok = overlay_pipe:flush()
    if not fok then
        overlay_disconnect()
        return false
    end
    return true
end

local function overlay_sync()
    if not overlay_connected then return end
    local tp = mp.get_property_number("time-pos", 0) or 0
    if tp < 0 then tp = 0 end
    return overlay_send(string.format(
        '{"type":"sync","time_pos":%.3f,"paused":%s,"speed":%.3f}',
        tp,
        mp.get_property_native("pause", false),
        mp.get_property_number("speed", 1.0)))
end

local function overlay_load_ass()
    if not overlay_connected then return end
    overlay_send(string.format('{"type":"load_ass","filepath":"%s"}', ass_path:gsub('\\', '\\\\'):gsub('"', '\\"')))
end

local function overlay_visiblility()
    if not overlay_connected then return end
    overlay_send(string.format('{"type":"set_enabled","enabled":%s}', show_danmaku))
end

local function overlay_delay()
    if not overlay_connected then return end
    overlay_send(string.format('{"type":"set_delay","delay":%.3f}', danmaku_delay))
end


local function overlay_hdr_mode()
    if not overlay_connected then return end
    overlay_send(string.format('{"type":"set_hdr","enabled":%s}', overlay_hdr and overlay_peak ~= "sdr"))
end

local function overlay_hdr_peak()
    if not overlay_connected then return end
    overlay_send(string.format('{"type":"set_hdr_peak","hdr_peak":%.1f}', tonumber(overlay_peak) or 400))
end

local function overlay_clear_danmaku()
    if not overlay_connected then return end
    overlay_send('{"type":"clear_danmaku"}')
end

local function overlay_shutdown()
    if not overlay_started then return end
    overlay_send('{"type":"shutdown"}')
    overlay_started = false
    overlay_connected = false
end

local function start_overlay()
    if overlay_started then return end
    mp.command_native_async({
        name = "subprocess",
        args = { "danmaku_overlay.exe", "--mpv-pid", tostring(pid), "--pipe", pipe_full, "--fps", "60" },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    })
    overlay_started = true
    local tries = 0
    local function tc()
        if overlay_connect() then
            overlay_sync()
            overlay_visiblility()
            overlay_delay()
            overlay_hdr_mode()
            overlay_hdr_peak()
        elseif tries < 50 then
            mp.add_timeout(0.2, tc)
        else
            mp.msg.error("overlay 连接超时")
            overlay_started = false
            return
        end
        tries = tries + 1
    end
    tc()
end

local function create_ass(comments, options, output)
    if not comments or not options then return false end
    local fout = io.open(output, "w")
    if not fout then return false end
    local hex = string.format("%02X", math.floor((1 - options.opacity) * 255))
    fout:write(
        "[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nTimer: 100.0000\nWrapStyle: 2\nScaledBorderAndShadow: yes\n"
    )
    fout:write(
        "\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, Strikeout, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n"
    )
    local common_style = string.format(
        "%s,%d,&H%sFFFFFF,&H%sFFFFFF,&H%s000000,&H%s000000,%s,0,0,0,100,100,0,0,1,%s,%s",
        options.fontname, options.fontsize, hex, hex, hex, hex, options.bold and "1" or "0", options.outline,
        options.shadow
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
    local display_range = options.displayarea * 1080
    for _, event in ipairs(comments) do
        local y = 0
        if event.move then
            y = event.move[2]
        elseif event.pos then
            y = event.pos[2]
        end
        if y <= display_range then
            local duration = event.move and options.scrolltime or options.fixtime
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

local function load_danmaku(json)
    danmaku_loaded = true
    if form == "osd" then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "delayset", danmaku_delay)
        return
    end
    local data = utils.parse_json(json)
    if create_ass(data.comments, data.options, ass_path) then
        if form == "sub" then
            if sid then
                mp.commandv("sub-reload", sid)
            else
                local max_sid = 0
                for _, track in ipairs(mp.get_property_native("track-list")) do
                    if track.type == "sub" and track.id > max_sid then
                        max_sid = track.id
                    end
                end
                sid = max_sid + 1
                mp.commandv("sub-add", ass_path, "auto", "ssdm_danmaku")
                mp.set_property_number("secondary-sid", sid)
            end
        elseif form == "overlay" then
            overlay_load_ass()
        end
        ass_loaded = true
    end
end

local function add_delay(value, no_osd)
    danmaku_delay = danmaku_delay + tonumber(value)
    if not no_osd then mp.osd_message("当前弹幕延迟: " .. (danmaku_delay > 0 and "+" or "") .. danmaku_delay .. "s") end
    if form == "osd" then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "delayset", danmaku_delay)
    elseif form == "sub" then
        mp.set_property_native("secondary-sub-delay", danmaku_delay)
    elseif form == "overlay" then
        overlay_delay()
    end
end

local function visibility_sync(init)
    if init then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "showset", "false")
        if sid then
            mp.commandv("sub-remove", sid)
            sid = nil
        end
        overlay_clear_danmaku()
        ass_loaded = false
    end
    if form == "osd" then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "showset", tostring(show_danmaku))
    elseif form == "sub" then
        mp.set_property_native("secondary-sub-visibility", show_danmaku)
    elseif form == "overlay" then
        overlay_visiblility()
    end
end

local function toggle_form(value)
    form = value or ({ osd = "sub", sub = "overlay", overlay = "osd" })[form]
    mp.set_property_native("user-data/ssdm-form", form)
    mp.osd_message("弹幕形式: " .. form)
    add_delay("0", true)
    visibility_sync(true)
    if form ~= "osd" and show_danmaku then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", danmaku_loaded and "refresh" or "load")
    end
end

local function toggle_visibility()
    show_danmaku = not show_danmaku
    mp.set_property_native("user-data/ssdm-visibility", show_danmaku)
    mp.osd_message(show_danmaku and "开启弹幕" or "关闭弹幕")
    mp.commandv("script-message-to", "uosc", "set", "ssdm_show_danmaku", show_danmaku and "on" or "off")
    visibility_sync()
    if not show_danmaku then return end
    if not danmaku_loaded then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "load")
    elseif form ~= "osd" and not ass_loaded then
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "refresh")
    end
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
    if not pad or Pading then return end
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
    pad = not pad
    mp.set_property_native("user-data/ssdm-pad", pad)
    mp.osd_message("自动填充黑边: " .. (pad and "开" or "关"))
    if pad then smart_pad() else mp.commandv("vf", "remove", "@Pad,@Format") end
end

local function init(_, loaded)
    if not loaded then return end
    local script = io.open(mp.command_native({ "expand-path", "~~/" }) .. "/scripts/uosc_danmaku/main.lua", 'a+')
    if script then
        local support = false
        for line in script:lines() do
            if line == "-- ssdm --" then
                support = true
                break
            end
        end
        if not support then
            mp.msg.info("检测到uosc_danmaku脚本未注入ssdm支持，开始注入...")
            script:write("\n\n")
            script:write([[
-- ssdm --
local ssdm_variables = {
    poll_danmaku = nil,
    prev_enabled = false,
    options = options,
    show_message = show_message,
    render_danmaku = render_danmaku
}
local ssdm_functions = {
    showset = function(show)
        ENABLED = show == "true"
        if ENABLED then show_danmaku_func() else hide_danmaku_func() end
    end,
    delayset = function(delay)
        if rebuild_convert_timer then
            rebuild_convert_timer:kill()
            rebuild_convert_timer = nil
        end
        for _, source in pairs(DANMAKU.sources) do
            if source.data and not source.blocked then
                source.delay_segments = { { start = 0, delay = tonumber(delay) } }
            end
        end
        rebuild_convert_timer = mp.add_timeout(0.1, function()
            convert_danmaku_to_ass_events(true)
            if ENABLED then render() end
        end)
    end,
    load = function()
        if ssdm_variables.poll_danmaku then
            ssdm_variables.poll_danmaku:kill()
            ssdm_variables.poll_danmaku = nil
            ENABLED = ssdm_variables.prev_enabled
        end
        ssdm_variables.prev_enabled = ENABLED
        ENABLED = true
        show_message = function() end
        render_danmaku = function() end
        local function restore()
            ENABLED = ssdm_variables.prev_enabled
            show_message = ssdm_variables.show_message
            render_danmaku = ssdm_variables.render_danmaku
        end
        if COMMENTS == nil or #COMMENTS == 0 then init(mp.get_property("path")) end
        ssdm_variables.show_message("弹幕加载中...", 10)
        local tries = 0
        local function poll()
            if (COMMENTS and #COMMENTS > 0) then
                if ssdm_variables.prev_enabled then show_danmaku_func() end
                ssdm_variables.show_message("弹幕加载成功，共计" .. #COMMENTS .. "条弹幕", 3)
                local data = utils.format_json({ comments = COMMENTS, options = ssdm_variables.options })
                mp.commandv("script-message-to", "ssdm", "load_danmaku", data)
                restore()
            elseif tries < 50 then
                ssdm_variables.poll_danmaku = mp.add_timeout(0.2, poll)
            else
                ssdm_variables.show_message("弹幕加载超时", 3)
                restore()
            end
            tries = tries + 1
        end
        poll()
    end,
    refresh = function()
        if rebuild_convert_timer then
            rebuild_convert_timer:kill()
            rebuild_convert_timer = nil
        end
        for _, source in pairs(DANMAKU.sources) do
            if source.data and not source.blocked then
                source.delay_segments = { { start = 0, delay = 0 } }
            end
        end
        convert_danmaku_to_ass_events(true)
        local data = utils.format_json({ comments = COMMENTS, options = ssdm_variables.options })
        mp.commandv("script-message-to", "ssdm", "load_danmaku", data)
    end
}
options = {}
setmetatable(options, {
    __index = function(_, k)
        return ssdm_variables.options[k]
    end,
    __newindex = function(_, k, v)
        ssdm_variables.options[k] = v
        local data = utils.format_json({ comments = COMMENTS, options = ssdm_variables.options })
        mp.commandv("script-message-to", "ssdm", "load_danmaku", data)
    end
})
mp.register_script_message("ssdm_command", function(fun, arg) ssdm_functions[fun](arg) end)]])
            mp.msg.info("ssdm支持注入成功，重启后即可使用ssdm相关功能")
        end
        script:close()
    end
    if mp.get_property_native("user-data/ssdm-visibility") then
        show_danmaku = true
    end
    local saved = mp.get_property_native("user-data/ssdm-form")
    if saved then
        form = saved
    else
        mp.set_property_native("user-data/ssdm-form", form)
    end
    saved = mp.get_property_native("user-data/ssdm-peak")
    if saved then
        overlay_peak = saved
    else
        mp.set_property_native("user-data/ssdm-peak", overlay_peak)
    end
    start_overlay()
    visibility_sync(true)
    mp.commandv("script-message-to", "uosc", "set", "ssdm_show_danmaku", show_danmaku and "on" or "off")
    if mp.get_property_native("user-data/ssdm-pad") then
        pad = true
    end
    mp.set_property_native("secondary-sub-ass-override", "yes")
    mp.observe_property("osd-dimensions", nil, smart_pad)
    mp.observe_property("pause", nil, overlay_sync)
    mp.observe_property("speed", nil, overlay_sync)
    mp.observe_property("seeking", nil, overlay_sync)
    mp.observe_property("video-target-params", "native", function(_, vtp)
        if not vtp or (vtp.gamma == "pq") == overlay_hdr or not overlay_connected then return end
        overlay_hdr = vtp.gamma == "pq"
        overlay_hdr_mode()
    end)
    mp.register_event("file-loaded", function()
        sid = nil
        overlay_clear_danmaku()
        danmaku_loaded = false
        if not show_danmaku then return end
        mp.commandv("script-message-to", "uosc_danmaku", "ssdm_command", "load")
    end)
    mp.register_event("shutdown", function()
        overlay_shutdown()
        os.remove(ass_path)
    end)
    mp.register_script_message('set', toggle_visibility)
    mp.register_script_message("set_ssdm_form", toggle_form)
    mp.register_script_message("add_ssdm_delay", add_delay)
    mp.register_script_message("set_ssdm_peak", function(peak)
        overlay_peak = peak
        mp.set_property_native("user-data/ssdm-peak", overlay_peak)
        overlay_hdr_peak()
    end)
    mp.register_script_message("load_danmaku", load_danmaku)
    mp.add_key_binding(nil, "toggle_form", toggle_form)
    mp.add_key_binding(nil, "toggle_visibility", toggle_visibility)
    mp.add_key_binding(nil, "toggle_pad", toggle_pad)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
