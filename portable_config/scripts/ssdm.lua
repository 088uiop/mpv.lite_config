local mp = require 'mp'
local utils = require 'mp.utils'

local sid = nil
local overlay_pipe = nil
local overlay_started = false
local overlay_connected = false
local overlay_hdr = false
local pad = false
local pading = false
local ass_loaded = false
local show_danmaku = false
local danmaku_loaded = false
local danmaku_delay = '0'
local form = 'osd'
local overlay_peak = 'sdr'
local pid = utils.getpid()
local pipe_full = string.format('//./pipe/danmaku_overlay_%d', pid)
local ass_path = os.getenv('TEMP') .. '/ssdm-danmaku-' .. pid .. '.ass'

local function overlay_connect()
    if overlay_connected then return true end
    local pipe = io.open(pipe_full, 'wb')
    if not pipe then return false end
    pipe:setvbuf('no')
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
    local data = json .. '\n'
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

local function overlay_sync(name, value)
    if not overlay_connected then return end
    return overlay_send(string.format(
        '{"type":"sync","time_pos":%.3f,"paused":%s,"speed":%.3f}',
        name == 'time-pos' and value or mp.get_property_number('time-pos', 0),
        name == 'pause' and value or mp.get_property_bool('pause', false),
        name == 'speed' and value or mp.get_property_number('speed', 1)))
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
    overlay_send(string.format('{"type":"set_delay","delay":%.3f}', tonumber(danmaku_delay)))
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
        name = 'subprocess',
        args = { 'danmaku_overlay', '--mpv-pid', tostring(pid), '--pipe', pipe_full, '--fps', '60' },
        detach = true
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
            mp.msg.error('overlay 连接超时')
            overlay_started = false
            return
        end
        tries = tries + 1
    end
    tc()
end

local function set_peak(peak)
    overlay_peak = peak
    mp.set_property_native('user-data/ssdm-peak', overlay_peak)
    overlay_hdr_mode()
    overlay_hdr_peak()
end

local function add_delay(value, no_osd)
    danmaku_delay = tostring(tonumber(danmaku_delay) + tonumber(value))
    if not no_osd then mp.osd_message('当前弹幕延迟: ' .. (tonumber(danmaku_delay) > 0 and '+' or '') .. danmaku_delay .. 's') end
    if form == 'osd' then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'delayset', danmaku_delay)
    elseif form == 'sub' then
        mp.set_property_native('secondary-sub-delay', danmaku_delay)
    elseif form == 'overlay' then
        overlay_delay()
    end
end

local function visibility_sync(init)
    if init then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'showset', 'false')
        if sid then
            mp.commandv('sub-remove', sid)
            sid = nil
        end
        overlay_clear_danmaku()
        ass_loaded = false
    end
    if form == 'osd' then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'showset', tostring(show_danmaku))
    elseif form == 'sub' then
        mp.set_property('secondary-sub-ass-override', 'yes')
        mp.set_property_bool('secondary-sub-visibility', show_danmaku)
    elseif form == 'overlay' then
        overlay_visiblility()
    end
end

local function toggle_visibility()
    show_danmaku = not show_danmaku
    mp.set_property_native('user-data/ssdm-visibility', show_danmaku)
    mp.osd_message(show_danmaku and '开启弹幕' or '关闭弹幕')
    mp.commandv('script-message-to', 'uosc', 'set', 'ssdm_show_danmaku', show_danmaku and 'on' or 'off')
    visibility_sync()
    if not show_danmaku then return end
    if not danmaku_loaded then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'load')
    elseif form ~= 'osd' and not ass_loaded then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'refresh')
    end
end

local function toggle_form(value)
    form = value or ({ osd = 'sub', sub = 'overlay', overlay = 'osd' })[form]
    mp.set_property_native('user-data/ssdm-form', form)
    mp.osd_message('弹幕形式: ' .. form)
    add_delay('0', true)
    visibility_sync(true)
    if form ~= 'osd' and show_danmaku then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'delayset', '0')
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'refresh', 'true')
    end
end

local function create_ass(comments, options, output)
    if not comments or not options then return false end
    local fout = io.open(output, 'w')
    if not fout then return false end
    local hex = string.format('%02X', math.floor((1 - options.opacity) * 255))
    fout:write(
        '[Script Info]\nScriptType: v4.00+\nPlayResX: 1920\nPlayResY: 1080\nTimer: 100.0000\nWrapStyle: 2\nScaledBorderAndShadow: yes\n'
    )
    fout:write(
        '\n[V4+ Styles]\nFormat: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, Strikeout, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding\n'
    )
    local common_style = string.format(
        '%s,%d,&H%sFFFFFF,&H%sFFFFFF,&H%s000000,&H%s000000,%s,0,0,0,100,100,0,0,1,%s,%s',
        options.fontname, options.fontsize, hex, hex, hex, hex, options.bold and '1' or '0', options.outline,
        options.shadow
    )
    fout:write(string.format('Style: R2L,%s,7,0,0,0,1\n', common_style))
    fout:write(string.format('Style: TOP,%s,8,0,0,0,1\n', common_style))
    fout:write(string.format('Style: BTM,%s,2,0,0,0,1\n', common_style))
    fout:write('\n[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n')
    local function format_time(seconds)
        if seconds < 0 then seconds = 0 end
        local h = math.floor(seconds / 3600)
        local m = math.floor((seconds % 3600) / 60)
        local s = seconds % 60
        return string.format('%d:%02d:%05.2f', h, m, s)
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
                local new_move = string.format('move(%s,%s,%s,%s)', x1, y1, x2 * 2, y2)
                event.text = event.text:gsub('move%([^)]+%)', new_move)
            end
            fout:write(string.format('Dialogue: 0,%s,%s,%s,,0,0,0,,%s\n', start_time, end_time, event.style, event.text))
        end
    end
    fout:close()
    return true
end

local function load_danmaku(json, init)
    local data = utils.parse_json(json) or {}
    danmaku_loaded = data.comments ~= nil and #data.comments > 0
    if form == 'osd' then
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'delayset', danmaku_delay)
    elseif create_ass(data.comments, data.options, ass_path) then
        if form == 'sub' then
            if sid then
                mp.commandv('sub-remove', sid)
                sid = nil
            end
            mp.commandv('sub-add', ass_path, 'auto', 'ssdm_danmaku')
            for _, track in ipairs(mp.get_property_native('track-list', {})) do
                if track.type == 'sub' and track['external-filename'] then
                    if track['external-filename']:find('ssdm%-danmaku%-' .. pid) then
                        sid = track.id
                        mp.set_property_number('secondary-sid', track.id)
                        break
                    end
                end
            end
        elseif form == 'overlay' then
            overlay_load_ass()
        end
        ass_loaded = true
    end
    if init == 'true' then
        show_danmaku = true
        mp.set_property_native('user-data/ssdm-visibility', true)
        mp.commandv('script-message-to', 'uosc', 'set', 'ssdm_show_danmaku', 'on')
        visibility_sync()
    end
end

local function unlock(aspect)
    mp.add_timeout(0.2, function()
        local w = mp.get_property_number('dwidth', 0)
        local h = mp.get_property_number('dheight', 0)
        if w * h == 0 or math.abs(w / h - aspect) < 0.01 then
            mp.set_property_bool('auto-window-resize', true)
            pading = false
            return
        end
        unlock(aspect)
    end)
end

local function smart_pad(_, osd_dimensions)
    if not pad or pading or not osd_dimensions then return end
    local w = mp.get_property_number('dwidth', 0)
    local h = mp.get_property_number('dheight', 0)
    local aspect = osd_dimensions.aspect
    if w * h == 0 or not aspect or math.abs(w / h - aspect) < 0.01 then return end
    mp.set_property_bool('auto-window-resize', false)
    pading = true
    mp.commandv('vf', 'remove', '@Pad,@Format')
    mp.commandv('vf', 'add', string.format('@Format:format=p010,@Pad:pad=aspect=%f:x=-1:y=-1', aspect))
    unlock(aspect)
end

local function toggle_pad()
    pad = not pad
    mp.set_property_native('user-data/ssdm-pad', pad)
    mp.osd_message('自动填充黑边: ' .. (pad and '开' or '关'))
    if pad then smart_pad() else mp.commandv('vf', 'remove', '@Pad,@Format') end
end

local function init(_, loaded)
    if not loaded then return end
    local script = io.open(mp.command_native({ 'expand-path', '~~/scripts/uosc_danmaku/main.lua' }), 'a+')
    if script then
        local support = false
        for line in script:lines() do
            if line == '-- ssdm --' then
                support = true
                break
            end
        end
        if not support then
            mp.msg.info('检测到uosc_danmaku脚本未注入ssdm支持，开始注入...')
            script:write('\n\n')
            script:write([[
-- ssdm --
local _enabled = false
local _options = options
local ssdm_funs = {
    load = function()
        if COMMENTS == nil or #COMMENTS == 0 then init(mp.get_property("path")) end
    end,
    refresh = function(covert, init)
        if covert then convert_danmaku_to_ass_events(true) end
        local data = utils.format_json({ comments = COMMENTS, options = _options })
        mp.commandv("script-message-to", "ssdm", "load_danmaku", data, tostring(init))
    end,
    showset = function(show)
        _enabled = show == "true"
        if ENABLED then show_danmaku_func() else hide_danmaku_func() end
    end,
    delayset = function(delay)
        if rebuild_convert_timer then rebuild_convert_timer:kill() end
        for _, source in pairs(DANMAKU.sources) do
            if source.data and not source.blocked then
                source.delay_segments = { { start = 0, delay = tonumber(delay) } }
            end
        end
        rebuild_convert_timer = mp.add_timeout(0.1, function()
            convert_danmaku_to_ass_events(true)
            if ENABLED then render() end
        end)
    end
}
rawset(_G, 'ENABLED', nil)
setmetatable(_G, {
    __index = function(t, k)
        if k == 'ENABLED' then return _enabled end
        return rawget(t, k)
    end,
    __newindex = function(t, k, v)
        if k == 'ENABLED' then return end
        rawset(t, k, v)
    end
})
options = setmetatable({}, {
    __index = function(_, k) return _options[k] end,
    __newindex = function(_, k, v)
        _options[k] = v
        ssdm_funs.refresh(true)
    end
})
load_danmaku = function(from_menu, no_osd)
    convert_danmaku_to_ass_events(no_osd)
    ssdm_funs.showset(tostring(_enabled))
    if not no_osd then show_loaded(true) end
    ssdm_funs.refresh(false, from_menu and not no_osd)
end
mp.register_script_message('ssdm_command', function(fun, arg) ssdm_funs[fun](arg) end)
]])
            mp.msg.info('ssdm支持注入成功，重启后即可使用ssdm相关功能')
        end
        script:close()
    end
    pad = mp.get_property_native('user-data/ssdm-pad', pad)
    form = mp.get_property_native('user-data/ssdm-form', form)
    overlay_peak = mp.get_property_native('user-data/ssdm-peak', overlay_peak)
    show_danmaku = mp.get_property_native('user-data/ssdm-visibility', show_danmaku)
    mp.set_property_native('user-data/ssdm-pad', pad)
    mp.set_property_native('user-data/ssdm-form', form)
    mp.set_property_native('user-data/ssdm-peak', overlay_peak)
    mp.set_property_native('user-data/ssdm-visibility', show_danmaku)
    start_overlay()
    visibility_sync(true)
    mp.commandv('script-message-to', 'uosc', 'set', 'ssdm_show_danmaku', show_danmaku and 'on' or 'off')
    mp.observe_property('osd-dimensions', 'native', smart_pad)
    mp.observe_property('pause', 'bool', overlay_sync)
    mp.observe_property('speed', 'number', overlay_sync)
    mp.observe_property('seeking', 'bool', overlay_sync)
    mp.observe_property('video-target-params', 'native', function(_, vtp)
        if not vtp or (vtp.gamma == 'pq') == overlay_hdr or not overlay_connected then return end
        overlay_hdr = vtp.gamma == 'pq'
        overlay_hdr_mode()
    end)
    mp.register_event('file-loaded', function()
        danmaku_loaded = false
        ass_loaded = false
        if not show_danmaku or form == 'osd' then return end
        mp.commandv('script-message-to', 'uosc_danmaku', 'ssdm_command', 'load')
    end)
    mp.register_event('end-file', function()
        sid = nil
        overlay_clear_danmaku()
    end)
    mp.register_event('shutdown', function()
        overlay_shutdown()
        os.remove(ass_path)
    end)
    mp.register_script_message('set', toggle_visibility)
    mp.register_script_message('set_ssdm_peak', set_peak)
    mp.register_script_message('add_ssdm_delay', add_delay)
    mp.register_script_message('set_ssdm_form', toggle_form)
    mp.register_script_message('load_danmaku', load_danmaku)
    mp.add_key_binding(nil, 'toggle_visibility', toggle_visibility)
    mp.add_key_binding(nil, 'toggle_form', toggle_form)
    mp.add_key_binding(nil, 'toggle_pad', toggle_pad)
    mp.unobserve_property(init)
end
mp.observe_property('user-data/__state_loaded__', 'bool', init)
