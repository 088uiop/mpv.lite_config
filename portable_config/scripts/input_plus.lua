local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local opt = {
    speed = 2,
    press_speed = false,
    speed_vs_off = false,
    seek_vs_off = false,
    skip_chapters = 'OP,ED,op,ed,opening,ending,Opening,Ending,オープニング,エンディング'
}
options.read_options(opt)

local seek_time = nil
local press_time = nil
local pressed = nil
local seek_over = nil
local original_speed = nil
local chap_skip = false
local openfile_alive = false
local seek_skip = false
local chap_keywords = {}
local menu_data = {}

local function explorer_load(type)
    if openfile_alive then return end
    local command = ({ Media = 'loadfile', AudioTrack = 'audio-add', Subtitle = 'sub-add' })[type]
    openfile_alive = true
    mp.command_native_async({
        name = 'subprocess',
        args = { 'openfile', type },
        playback_only = false,
        capture_stdout = true
    }, function(_, result)
        openfile_alive = false
        for filename in string.gmatch(result.stdout, '[^\r\n]+') do
            filename = filename:gsub('^%s*(.-)%s*$', '%1')
            if filename ~= '' then mp.commandv(command, filename) end
        end
    end)
end

local function chap_skip_check(_, value)
    if not chap_skip or not value then return end
    for _, kw in ipairs(chap_keywords) do
        if string.find(value, kw) then
            mp.commandv('add', 'chapter', '+1')
            mp.osd_message('已跳过章节: ' .. value)
            break
        end
    end
end

local function chap_skip_toggle()
    chap_skip = not chap_skip
    mp.set_property_native('user-data/chap-skip', chap_skip)
    mp.osd_message('自动跳过设定章节: ' .. (chap_skip and '开' or '关'))
    chap_skip_check(_, mp.get_property('chapter-metadata/TITLE'))
end

local function toggle_vs(state)
    for _, filter in ipairs(mp.get_property_native('vf', {})) do
        if filter.label and filter.label:find('^VS%d+$') and filter.enabled ~= state then
            mp.commandv('vf', 'toggle', '@' .. filter.label)
        end
    end
end

local function speed_auto(tab)
    if tab.event == 'down' then
        local function start()
            if opt.speed_vs_off then toggle_vs(false) end
            original_speed = mp.get_property_number('speed', 1)
            mp.set_property_number('speed', original_speed * opt.speed)
        end
        if opt.press_speed then
            press_time = mp.get_time()
            pressed = mp.add_timeout(0.2, start)
        else
            start()
        end
    elseif tab.event == 'up' then
        if opt.press_speed then
            if mp.get_time() - press_time < 0.2 then mp.commandv('seek', seek_time) end
            press_time = nil
            if pressed then pressed:kill() end
        end
        if original_speed then
            if opt.speed_vs_off then toggle_vs(true) end
            mp.set_property_number('speed', original_speed)
            original_speed = nil
        end
    end
end

local function speed_auto_bullet(tab)
    if tab.event == 'down' then
        original_speed = mp.get_property_number('speed', 1)
        mp.set_property_number('speed', original_speed * 0.5)
    elseif tab.event == 'up' then
        if original_speed then
            mp.set_property_number('speed', original_speed)
            original_speed = nil
        end
    end
end

local function show_ytdl_settings_menu()
    local current_settings = mp.get_property_native('ytdl-raw-options', {})
    menu_data = {
        type = 'ytdl_settings',
        title = 'ytdl设置',
        callback = { mp.get_script_name(), 'update_ytdl_settings_menu' },
        items = {
            { title = '代理地址', value = '输入代理服务器地址', hint = current_settings.proxy or '无' },
            { title = 'Cookies路径', value = '输入Cookies物理路径', hint = current_settings.cookies or '无' },
            { title = '手动更新Cookies' }
        }
    }
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data))
end

local function update()
    mp.command_native({
        name = 'subprocess',
        args = { 'cmd', '/c', 'start', '""', 'cmd', '/c', mp.command_native({ 'expand-path', '~~/../updater.bat' }) },
        detach = true
    })
    mp.command_native_async({
        name = 'subprocess',
        args = { 'taskkill', '/f', '/im', 'mpv.exe', '/t' },
        detach = true
    })
end

local function init(_, loaded)
    if not loaded then return end
    chap_skip = mp.get_property_native('user-data/chap-skip', chap_skip)
    for str in string.gmatch(opt.skip_chapters, '([^,]+)') do chap_keywords[#chap_keywords + 1] = str .. '$' end
    if opt.press_speed then
        local input_conf = io.open(mp.command_native({ 'expand-path', '~~/input.conf' }), 'r')
        if not input_conf then return nil end
        for line in input_conf:lines() do
            line = line:match('^%s*(.-)%s*$')
            if line and not line:find('^#') and line ~= '' then
                if line:find('seek') and not line:find('-') and not line:find('exact') then
                    seek_time = line:match('seek.-(%d+)')
                    mp.add_forced_key_binding(line:match('^[%S]+'), nil, speed_auto, { complex = true })
                    break
                end
            end
        end
        input_conf:close()
    end
    if opt.seek_vs_off then
        mp.register_event('file-loaded', function() seek_skip = true end)
        mp.observe_property('seeking', 'bool', function(_, seeking)
            if seek_skip then
                if not seeking then seek_skip = false end
                return
            end
            if seeking then toggle_vs(false) end
            if seek_over then seek_over:kill() end
            seek_over = mp.add_timeout(1, function()
                if mp.get_property_bool('pause') then seek_skip = true end
                toggle_vs(true)
            end)
        end)
    end
    mp.observe_property('chapter-metadata/TITLE', 'string', chap_skip_check)
    mp.register_script_message('update_ytdl_settings_menu', function(json)
        local event = utils.parse_json(json)
        local ytdl_settings = mp.get_property_native('ytdl-raw-options', {})
        if event.type == 'activate' then
            if event.index == 3 then
                mp.command_native_async({
                    name = 'subprocess',
                    args = { 'notepad', ytdl_settings.cookies },
                    playback_only = false
                })
                mp.commandv('script-message-to', 'uosc', 'close-menu')
            else
                menu_data.search_debounce = 'submit'
                menu_data.search_style = 'palette'
                menu_data.on_search = 'callback'
                menu_data.title = event.value
                for _, item in ipairs(menu_data.items) do item.active = false end
                menu_data.items[event.index].active = true
                mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu_data))
            end
        elseif event.type == 'search' then
            for index, item in ipairs(menu_data.items) do
                if item.active then
                    if event.query == '' then
                        ytdl_settings[({ 'proxy', 'cookies' })[index]] = nil
                    else
                        ytdl_settings[({ 'proxy', 'cookies' })[index]] = event.query
                    end
                    mp.set_property_native('ytdl-raw-options', ytdl_settings)
                    item.hint = event.query == '' and '无' or event.query
                    break
                end
            end
            mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data))
        end
    end)
    mp.register_script_message('explorer_load', explorer_load)
    mp.register_script_message('show_ytdl_settings_menu', show_ytdl_settings_menu)
    mp.add_key_binding(nil, 'chap_skip_toggle', chap_skip_toggle)
    mp.add_key_binding(nil, 'speed_auto', speed_auto, { complex = true })
    mp.add_key_binding(nil, 'speed_auto_bullet', speed_auto_bullet, { complex = true })
    mp.add_key_binding(nil, 'update', update)
    mp.unobserve_property(init)
end
mp.observe_property('user-data/__state_loaded__', 'bool', init)
