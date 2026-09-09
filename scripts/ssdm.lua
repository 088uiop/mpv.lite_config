local mp = require 'mp'
local ffi = require 'ffi'
local utils = require 'mp.utils'

local form = "osd"
local sid = nil
local overlay_pipe = nil
local overlay_started = false
local overlay_connected = false
local overlay_hdr = false
local pad = false
local updating_uosc_danmaku_data = false
local show_danmaku = false
local danmaku_delay = 0
local overlay_peak = "sdr"
local pid = utils.getpid()
local config_dir = mp.command_native({ "expand-path", "~~/" })
local pipe_full = string.format("\\\\.\\pipe\\mpv_danmaku_%d", pid)
local ass_path = utils.join_path(os.getenv("TEMP"), "ssdm-danmaku-" .. pid .. ".ass")
local uosc_danmaku_main_path = config_dir .. "/scripts/uosc_danmaku/main.lua"
local uosc_danmaku_data = { enabled = false, comments = nil, options = nil }

INVALID_HANDLE = ffi.cast("void*", -1)
ffi.cdef([[
        typedef void* HANDLE;
        typedef unsigned long DWORD;
        typedef wchar_t WCHAR;
        typedef int BOOL;
        HANDLE __stdcall CreateFileW(const WCHAR*, DWORD, DWORD, void*, DWORD, DWORD, HANDLE);
        BOOL   __stdcall WriteFile(HANDLE, const void*, DWORD, DWORD*, void*);
        BOOL   __stdcall CloseHandle(HANDLE);
        DWORD  __stdcall GetLastError(void);
        void   __stdcall Sleep(unsigned long);
        void*  __stdcall ShellExecuteW(void*, const WCHAR*, const WCHAR*, const WCHAR*, const WCHAR*, int);
    ]])

local function str_wide(s)
    local w = ffi.new("WCHAR[?]", #s + 1)
    for i = 0, #s - 1 do w[i] = string.byte(s, i + 1) end
    w[#s] = 0
    return w
end

local function overlay_connect()
    if overlay_connected then return true end
    local h = ffi.C.CreateFileW(str_wide(pipe_full),
        0x80000000 + 0x40000000, 0, nil, 3, 0, nil)
    if h == INVALID_HANDLE then return false end
    overlay_pipe = h
    overlay_connected = true
    return true
end

local function overlay_disconnect()
    if overlay_pipe and overlay_pipe ~= INVALID_HANDLE then
        ffi.C.CloseHandle(overlay_pipe)
    end
    overlay_pipe = nil
    overlay_connected = false
end

local function overlay_send(json)
    if not overlay_connected then return false end
    local data = json .. "\n"
    local buf = ffi.new("char[?]", #data + 1)
    ffi.copy(buf, data, #data)
    local n = ffi.new("DWORD[1]", 0)
    local ok = ffi.C.WriteFile(overlay_pipe, buf, #data, n, nil)
    if not ok or n[0] ~= #data then
        local gle = ffi.C.GetLastError()
        if gle == 109 or gle == 232 then overlay_disconnect() end
        return false
    end
    return true
end

local function jesc(s)
    return (s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'))
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
    overlay_send(string.format('{"type":"load_ass","filepath":"%s"}', jesc(ass_path)))
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

local function overlay_shutdown()
    if not overlay_started then return end
    overlay_send('{"type":"shutdown"}')
    overlay_started = false
    overlay_connected = false
end

local function start_overlay()
    if overlay_started then return end
    local cmd = string.format('--mpv-pid %d --pipe %s --fps 60', pid, pipe_full)
    local shell32 = ffi.load("shell32")
    local r = shell32.ShellExecuteW(nil, str_wide("open"), str_wide("danmaku_overlay.exe"),
        str_wide(cmd), nil, 1)
    if tonumber(ffi.cast("intptr_t", r)) <= 32 then
        mp.msg.error("启动 overlay 失败 (code<32)")
        return false
    end
    overlay_started = true
    local tries = 0
    local function tc()
        if overlay_connect() then
            mp.add_timeout(0.2, function()
                overlay_sync()
                overlay_load_ass()
                overlay_visiblility()
                overlay_delay()
                overlay_hdr_mode()
                overlay_hdr_peak()
            end)
        elseif tries < 50 then
            mp.add_timeout(0.2, tc)
        else
            mp.msg.error("overlay 连接超时")
            overlay_started = false
        end
        tries = tries + 1
    end
    tc()
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

local function receive_data(data)
    uosc_danmaku_data = utils.parse_json(data)
    updating_uosc_danmaku_data = false
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
    if AP then AP:kill() end
    if form == "osd" then return end
    updating_uosc_danmaku_data = true
    mp.commandv("script-message-to", "uosc_danmaku", "send_data")
    set_uosc_danmaku(true, function()
        AP = mp.add_timeout(0.2, function()
            if mp.get_property_native("user-data/uosc_danmaku/has-danmaku") then
                local success = process_danmaku(uosc_danmaku_data.comments, ass_path)
                if success then
                    set_uosc_danmaku(false, function()
                        if form == "sub" then
                            mp.commandv("sub-add", ass_path, "auto", "ssdm_danmaku")
                            sid = get_max_sid()
                            mp.set_property_number("secondary-sid", sid)
                        elseif form == "overlay" then
                            overlay_load_ass()
                        end
                    end)
                    return
                end
            end
            assprocess()
        end)
    end)
end

local function add_delay(value)
    danmaku_delay = danmaku_delay + tonumber(value)
    mp.osd_message("当前弹幕延迟: " .. (danmaku_delay > 0 and "+" or "") .. danmaku_delay .. "s")
    if form == "osd" then
        mp.commandv("script-message", "danmaku-delay", 0)
        mp.commandv("script-message", "danmaku-delay", danmaku_delay)
    elseif form == "sub" then
        mp.set_property_native("secondary-sub-delay", danmaku_delay)
    elseif form == "overlay" then
        overlay_delay()
    end
end

local function toggle_form(value, init)
    form = value or ({ osd = "sub", sub = "overlay", overlay = "osd" })[form]
    mp.set_property_native("user-data/ssdm-form", form)
    if not init then mp.osd_message("弹幕形式: " .. form) end
    if sid then
        mp.commandv("sub-remove", sid)
        sid = nil
    end
    overlay_shutdown()
    if form == "osd" then
        set_uosc_danmaku(show_danmaku)
    elseif form == "sub" then
        mp.set_property_native("secondary-sub-visibility", show_danmaku)
    elseif form == "overlay" then
        start_overlay()
    end
    if init then return end
    assprocess()
end

local function toggle_visibility()
    show_danmaku = not show_danmaku
    mp.set_property_native("user-data/ssdm-visibility", show_danmaku)
    mp.osd_message(show_danmaku and "开启弹幕" or "关闭弹幕")
    mp.commandv("script-message-to", "uosc", "set", "ssdm_show_danmaku", show_danmaku and "on" or "off")
    if form == "osd" then
        set_uosc_danmaku(show_danmaku)
    elseif form == "sub" then
        mp.set_property_native("secondary-sub-visibility", show_danmaku)
    elseif form == "overlay" then
        overlay_visiblility()
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
                '\n-- ssdm support --\nlocal _options = options\noptions = {}\nsetmetatable(options, {\n    __index = function(_, k)\n        return _options[k]\n    end,\n    __newindex = function(_, k, v)\n        _options[k] = v\n        mp.commandv("script-message-to", "ssdm", "danmaku_refresh")\n    end\n})\nmp.register_script_message("send_data", function()\n    local data = { enabled = ENABLED, comments = COMMENTS, options = _options }\n    mp.commandv("script-message-to", "ssdm", "receive_data", utils.format_json(data))\nend)\n'
            )
            mp.msg.info("ssdm支持注入成功，重启后即可使用次字幕弹幕相关功能")
        end
        script:close()
    end
    local saved = mp.get_property_native("user-data/ssdm-form")
    if saved then
        form = saved
        toggle_form(form, true)
    else
        mp.set_property_native("user-data/ssdm-form", form)
    end
    saved = mp.get_property_native("user-data/ssdm-peak")
    if saved then
        overlay_peak = saved
        overlay_hdr_peak()
    else
        mp.set_property_native("user-data/ssdm-peak", overlay_peak)
    end
    if mp.get_property_native("user-data/ssdm-visibility") then
        show_danmaku = true
    end
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
    mp.register_event("file-loaded", assprocess)
    mp.register_event("shutdown", function()
        os.remove(ass_path)
        overlay_shutdown()
    end)
    mp.register_script_message('set', toggle_visibility)
    mp.register_script_message("set_ssdm_form", toggle_form)
    mp.register_script_message("add_ssdm_delay", add_delay)
    mp.register_script_message("set_ssdm_peak", function(peak)
        overlay_peak = peak
        mp.set_property_native("user-data/ssdm-peak", overlay_peak)
        overlay_hdr_mode()
        overlay_hdr_peak()
    end)
    mp.register_script_message("danmaku_refresh", assprocess)
    mp.register_script_message("receive_data", receive_data)
    mp.add_key_binding(nil, "toggle_form", toggle_form)
    mp.add_key_binding(nil, "toggle_visibility", toggle_visibility)
    mp.add_key_binding(nil, "toggle_pad", toggle_pad)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
