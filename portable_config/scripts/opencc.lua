local mp = require 'mp'
local utils = require 'mp.utils'

local state = 0
local original_sid = nil
local converted_sid = nil
local pid = utils.getpid()
local temp_path = os.getenv('TEMP')

local function split_ass_dialogue(ass_path)
    local ass = io.open(ass_path, 'r')
    if not ass then return {}, '' end
    local lines, events = {}, {}
    local tmp_txt = os.tmpname() .. '.txt'
    for line in ass:lines() do
        line = line:gsub('[\r\n]', '')
        if line:match('^Dialogue:') then
            local pos = 1
            for _ = 1, 9 do
                local next = line:find(',', pos)
                if not next then break end
                pos = next + 1
            end
            local prefix, text = line:sub(1, pos - 1), line:sub(pos)
            table.insert(lines, { type = 'event', prefix = prefix })
            table.insert(events, text)
        else
            table.insert(lines, { type = 'other', text = line })
        end
    end
    ass:close()
    local txt = io.open(tmp_txt, 'w')
    if txt then
        txt:write(table.concat(events, '\n'))
        txt:close()
    end
    return lines, tmp_txt
end

local function convert_sub()
    original_sid = mp.get_property_number('sid')
    if state == 0 or not original_sid then return end
    local track = nil
    for _, t in ipairs(mp.get_property_native('track-list')) do
        if t.type == 'sub' and t.id == original_sid then
            track = t
            break
        end
    end
    if not track or track.title == 'opencc' then return end
    local codec = (track.codec or ''):find('ass') and 'ass' or 'srt'
    local convert_sub_path = temp_path .. '/convert-sub-' .. pid .. '.' .. codec
    local video_path = mp.get_property('path')
    mp.command_native_async({
        name = 'subprocess',
        args = track.external and
            { 'ffmpeg', '-y', '-i', track['external-filename'], '-c:s', codec and 'ass' or 'srt', convert_sub_path } or
            { 'ffmpeg', '-y', '-i', video_path, '-map', '0:' .. track['ff-index'], '-c:s', codec, convert_sub_path },
        playback_only = false,
        capture_stdout = true,
        capture_stderr = true
    }, function()
        local config_path = mp.command_native({ 'expand-path', '~~/' })
            .. '/../' .. (state == 1 and 't2s.json' or 's2t.json')
        local max_sid = 0
        for _, t in ipairs(mp.get_property_native('track-list')) do
            if t.type == 'sub' and t.id > max_sid then
                max_sid = t.id
            end
        end
        local lines = {}
        local convert_path = convert_sub_path
        if codec == 'ass' then lines, convert_path = split_ass_dialogue(convert_sub_path) end
        mp.command_native_async({
            name = 'subprocess',
            args = { 'opencc', '-i', convert_path, '-o', convert_path, '-c', config_path },
            playback_only = false
        }, function()
            if codec == 'ass' then
                local tmp_txt = io.open(convert_path, 'r')
                local ass = io.open(convert_sub_path, 'w')
                if tmp_txt and ass then
                    for _, line in ipairs(lines) do
                        if line.type == 'event' then
                            local text = tmp_txt:read('*l') or ''
                            ass:write(line.prefix .. text .. '\n')
                        else
                            ass:write(line.text .. '\n')
                        end
                    end
                    tmp_txt:close()
                    ass:close()
                end
                os.remove(convert_path)
            end
            converted_sid = max_sid + 1
            mp.commandv('sub-add', convert_sub_path, 'select', 'opencc')
        end)
    end)
end

local function toggle_convert_mode(mode)
    state = tonumber(mode) or (state + 1) % 3
    mp.set_property_native('user-data/opencc-mode', state)
    if converted_sid then
        mp.commandv('sub-remove', converted_sid)
        converted_sid = nil
        mp.set_property('sid', original_sid)
    end
    convert_sub()
    local status_msg = ({ [0] = '关闭', [1] = '繁转简', [2] = '简转繁' })[state]
    mp.osd_message('字幕繁简转换: ' .. status_msg)
end

local function init(_, loaded)
    if not loaded then return end
    local saved = mp.get_property_native('user-data/opencc-mode')
    if saved then
        state = saved
    else
        mp.set_property_native('user-data/opencc-mode', state)
    end
    mp.register_event('file-loaded', function()
        original_sid = nil
        converted_sid = nil
        convert_sub()
    end)
    mp.register_event('shutdown', function()
        os.remove(temp_path .. '/convert-sub-' .. pid .. '.ass')
        os.remove(temp_path .. '/convert-sub-' .. pid .. '.srt')
    end)
    mp.register_script_message('toggle_opencc_mode', toggle_convert_mode)
    mp.unobserve_property(init)
end

mp.observe_property('user-data/__state_loaded__', 'bool', init)
