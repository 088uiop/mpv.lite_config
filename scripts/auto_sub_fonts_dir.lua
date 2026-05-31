local mp = require 'mp'
local utils = require 'mp.utils'

local fonts_dir_init = mp.get_property_native("sub-fonts-dir")
local fonts_dir_cur = fonts_dir_init
local already_extracted = false

local function set_fonts_dir(dir)
    if dir ~= fonts_dir_cur then
        mp.set_property("sub-fonts-dir", dir)
        fonts_dir_cur = dir
        mp.msg.info("使用字体文件夹: " .. dir)
    end
end

local function extract_archive(src, dst, cb)
    mp.command_native_async({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = { "7z", "x", src, "-o" .. dst, "-y" }
    }, function(_, val, err)
        if err or not val then
            mp.msg.error("解压失败: " .. src)
            cb(false)
            return
        end
        mp.msg.info("成功解压: " .. src .. " → " .. dst)
        cb(true)
    end)
end

local function has_font_file_in(dir)
    local files = utils.readdir(dir, "files") or {}
    for _, f in ipairs(files) do
        local lf = f:lower()
        if lf:find("%.ttf$") or lf:find("%.otf$") or lf:find("%.ttc$") then
            return true
        end
    end
    return false
end

local function find_archive_in(dir)
    local files = utils.readdir(dir, "files") or {}
    for _, f in ipairs(files) do
        local lf = f:lower()
        if lf:find("%.7z$") or lf:find("%.zip$") or lf:find("%.rar$") then
            return utils.join_path(dir, f)
        end
    end
    return nil
end

local function find_fonts_dir_recursive(dir, depth)
    depth = depth or 0
    if depth > 3 then return nil end
    if has_font_file_in(dir) then return dir end
    local subdirs = utils.readdir(dir, "dirs") or {}
    for _, name in ipairs(subdirs) do
        if name:lower():find("fonts") then
            local found = find_fonts_dir_recursive(
                utils.join_path(dir, name), depth + 1)
            if found then return found end
        end
    end
    for _, name in ipairs(subdirs) do
        if not name:lower():find("fonts") then
            local found = find_fonts_dir_recursive(
                utils.join_path(dir, name), depth + 1)
            if found then return found end
        end
    end
    return nil
end

local function check_fonts_dir(dir)
    local fonts_path = utils.join_path(dir, "fonts")
    if utils.readdir(fonts_path) then
        local found = find_fonts_dir_recursive(fonts_path)
        if found then
            set_fonts_dir(found)
            return true
        end
        if not already_extracted then
            local arc = find_archive_in(fonts_path)
            if arc then
                extract_archive(arc, fonts_path, function(ok)
                    if ok then
                        already_extracted = true
                        local fd = find_fonts_dir_recursive(fonts_path)
                        if fd then set_fonts_dir(fd) end
                    end
                end)
                return true
            end
        end
    end
    for _, name in ipairs(utils.readdir(dir, "dirs") or {}) do
        if name:lower():find("fonts") then
            local p = utils.join_path(dir, name)
            if utils.readdir(p) then
                local fd = find_fonts_dir_recursive(p)
                if fd then
                    set_fonts_dir(fd)
                    return true
                end
            end
        end
    end
    return false
end

local function update_fonts_dir()
    local path = mp.get_property_native("path")
    if not path then return end
    local dir = utils.split_path(path)
    if not dir then return end
    if check_fonts_dir(dir) or already_extracted then return end
    local files = utils.readdir(dir, "files") or {}
    for _, name in ipairs(files) do
        local lname = name:lower()
        if lname:find("fonts") and
            (lname:find("%.7z$") or lname:find("%.zip$") or lname:find("%.rar$")) then
            local arc = utils.join_path(dir, name)
            local dst = utils.join_path(dir, name:gsub("%.[^.]+$", ""))
            mp.command_native_async({
                name = "subprocess",
                args = { "cmd", "/c", "mkdir", dst }
            }, function(_, _, err)
                if err then return end
                extract_archive(arc, dst, function(ok)
                    if ok then
                        already_extracted = true
                        local fd = find_fonts_dir_recursive(dst)
                        if fd then
                            set_fonts_dir(fd)
                        else
                            check_fonts_dir(dir)
                        end
                    end
                end)
            end)
            return
        end
    end
    if fonts_dir_cur ~= fonts_dir_init then
        mp.set_property("sub-fonts-dir", fonts_dir_init)
        fonts_dir_cur = fonts_dir_init
        mp.msg.info("恢复默认字体路径")
    end
end

mp.register_event("file-loaded", update_fonts_dir)
