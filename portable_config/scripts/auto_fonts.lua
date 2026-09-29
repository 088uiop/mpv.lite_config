local mp = require 'mp'
local utils = require 'mp.utils'

local video_dir = nil
local default_dir = mp.get_property('sub-fonts-dir', '')

local function set_dir(dir)
    mp.set_property('sub-fonts-dir', dir or default_dir)
    if dir then mp.msg.info('当前字体目录: ' .. dir) end
end

local function scan(dir, depth)
    local archive = nil
    local layer = { dir }
    local count_limit = 2048
    while depth > 0 and #layer > 0 do
        local new_layer = {}
        for _, predir in ipairs(layer) do
            for _, file in ipairs(utils.readdir(predir, 'files') or {}) do
                if count_limit == 0 then return end
                local namelow = file:lower()
                local suffix = namelow:match('%.(%w+)$')
                if suffix == 'ttf' or suffix == 'ttc' or suffix == 'otf' or suffix == 'otc' then
                    return predir
                elseif not archive and namelow:find('fonts') and (suffix == 'zip' or suffix == 'rar' or suffix == '7z') then
                    archive = utils.join_path(predir, file)
                end
                count_limit = count_limit - 1
            end
            for _, floder in ipairs(utils.readdir(predir, 'dirs') or {}) do
                new_layer[#new_layer + 1] = utils.join_path(predir, floder)
            end
        end
        layer = new_layer
        depth = depth - 1
    end
    if archive then
        local dst = archive:gsub('%.[^.]+$', '')
        mp.command_native({
            name = 'subprocess',
            args = { '7z', 'x', archive, '-o' .. dst, '-y' },
            playback_only = false,
            capture_stdout = true,
            capture_stderr = true
        })
        mp.msg.info('解压: ' .. archive .. ' → ' .. dst)
        return scan(dst, 2)
    end
end

mp.register_event('file-loaded', function()
    local path = mp.get_property('path')
    if not path then return end
    local dir = utils.split_path(path)
    if video_dir == dir then return end
    video_dir = dir
    local predir = utils.split_path(dir:gsub("[/\\]+$", ""))
    set_dir(scan(video_dir, 3) or scan(predir, 3))
end)
