local mp = require 'mp'
local ffi = require 'ffi'
local bit = require 'bit'
local utils = require 'mp.utils'
local options = require 'mp.options'

local config = {
    socket = "",
    tnpath = "",
    max_height = 200,
    max_width = 200,
    overlay_id = 42,
    spawn_first = true,
    quit_after_inactivity = 0,
    network = false,
    audio = false,
    hwdec = "yes",
    sw_threads = 0,
    binpath = "default",
    min_duration = 0,
    precise = 0,
    quality = 1,
    frequency = 0.125,
}
options.read_options(config)

local unique_id = utils.getpid()
config.socket = config.socket .. unique_id
config.tnpath = (config.tnpath == "" and (os.getenv("TEMP") or "/tmp") .. "/thumbfast.out" or config.tnpath) .. unique_id

local winapi = {
    C = ffi.C,
    CP_UTF8 = 65001,
    GENERIC_WRITE = 0x40000000,
    OPEN_EXISTING = 3,
    PIPE_NOWAIT = ffi.new("unsigned long[1]", 1),
    INVALID_HANDLE_VALUE = ffi.cast("void*", -1),
    written = ffi.new("unsigned long[1]"),
    flags = bit.bor(0x80000000, 0x20000000)
}

ffi.cdef [[
    void* __stdcall CreateFileW(const wchar_t*, unsigned long, unsigned long, void*, unsigned long, unsigned long, void*);
    bool  __stdcall WriteFile(void*, const void*, unsigned long, unsigned long*, void*);
    bool  __stdcall CloseHandle(void*);
    bool  __stdcall SetNamedPipeHandleState(void*, unsigned long*, unsigned long*, unsigned long*);
    int   __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, wchar_t*, int);
]]

local function to_wide(str)
    if not str or str == "" then return "" end
    local len = winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, str, -1, nil, 0)
    if len > 0 then
        local wstr = ffi.new("wchar_t[?]", len)
        if winapi.C.MultiByteToWideChar(winapi.CP_UTF8, 0, str, -1, wstr, len) > 0 then
            return wstr
        end
    end
    return ""
end
winapi.socket_path = to_wide("\\\\.\\pipe\\" .. config.socket)

local state = {
    spawned = false,
    disabled = false,
    spawn_waiting = false,
    spawn_working = false,
    thumbnail_ready = false,
    show_overlay = false,
    script_name = nil,
    effective_width = config.max_width,
    effective_height = config.max_height,
    cursor_x = nil,
    cursor_y = nil,
    last_cursor_x = nil,
    last_cursor_y = nil,
    real_width = nil,
    real_height = nil,
    last_real_width = nil,
    last_real_height = nil,
    has_video = 0,
    last_has_video = 0,
    last_seek_time = nil,
    auto_run = true,
    hwdec = true,
    seek_count = 0,
    properties = {},
}

local function exec_subprocess(args, async, callback)
    local cmd = {
        name = "subprocess",
        args = args,
        playback_only = async,
        capture_stdout = not async
    }
    if async then
        return mp.command_native_async(cmd, callback or function() end)
    else
        return mp.command_native(cmd)
    end
end

local function send_command(cmd)
    if not state.spawned then return false end
    local pipe = winapi.C.CreateFileW(winapi.socket_path, winapi.GENERIC_WRITE, 0, nil,
        winapi.OPEN_EXISTING, winapi.flags, nil)

    if pipe ~= winapi.INVALID_HANDLE_VALUE then
        local buffer = cmd .. "\n"
        winapi.C.SetNamedPipeHandleState(pipe, winapi.PIPE_NOWAIT, nil, nil)
        local success = winapi.C.WriteFile(pipe, buffer, #buffer + 1, winapi.written, nil)
        winapi.C.CloseHandle(pipe)
        return success
    end
    return false
end

local function cleanup_files()
    os.remove(config.tnpath)
    os.remove(config.tnpath .. ".bgra")
    os.remove(config.tnpath .. ".tmp")
end

local function update_info(width, height)
    local video_track = state.properties["current-tracks/video"]
    local is_image = video_track and video_track.image
    local is_albumart = video_track and video_track.albumart

    state.disabled = not state.auto_run or
        (width or 0) == 0 or (height or 0) == 0 or
        state.has_video == 0 or
        (state.properties["demuxer-via-network"] and not config.network) or
        (is_albumart and not config.audio) or
        (is_image and not is_albumart) or
        (mp.get_property_number("duration", 0) <= config.min_duration and config.min_duration > 0)

    mp.command_native_async({
        "script-message",
        "thumbfast-info",
        utils.format_json({
            width = width,
            height = height,
            disabled = state.disabled,
            available = true,
            socket = config.socket,
            tnpath = config.tnpath,
            overlay_id = config.overlay_id
        })
    }, function() end)
end

local function calculate_dimensions()
    local video_params = state.properties["video-params"]
    if not video_params or not video_params.w or not video_params.h then
        return
    end

    local display_width = mp.get_property_number("display-width", 0)
    local display_height = mp.get_property_number("display-height", 0)
    local scale = 1

    if state.properties["hidpi-window-scale"] then
        scale = state.properties["display-hidpi-scale"] or 1
    elseif display_height > 0 and display_width / display_height >= 2 then
        scale = display_height / 1080
    end

    local ratio = math.min(config.max_width / video_params.w, config.max_height / video_params.h) * scale
    state.effective_width = math.floor(video_params.w * ratio + 0.5)
    state.effective_height = math.floor(video_params.h * ratio + 0.5)
end

local function build_video_filter()
    local quality = tonumber(config.quality) or 1
    local signal_peak = mp.get_property_number("video-params/sig-peak", 1)
    local dimensions = state.effective_width .. ":h=" .. state.effective_height
    local format_suffix = ",format=fmt=bgra"

    if signal_peak <= 1 then
        local prefix = quality > 1 and "gpu=api=vulkan:w=" or "scale=w="
        return prefix .. dimensions .. format_suffix
    end

    local dv_profile = mp.get_property_number("current-tracks/video/dolby-vision-profile", 0)

    if dv_profile == 5 and quality > 2 then
        return "scale=w=" .. dimensions ..
            ",libplacebo=colorspace=bt709:color_primaries=bt709:color_trc=bt709:tonemapping=hable" ..
            format_suffix
    end

    if dv_profile == 8 then
        local dv_level = mp.get_property_number("current-tracks/video/dolby-vision-level", 0)
        local max_cll = mp.get_property_number("video-out-params/max-cll", 0)

        if dv_level == 7 and max_cll == 0 and quality < 2 then
            return "scale=w=" .. dimensions ..
                ",tonemap=tonemap=hable,zscale=transfer=linear,format=fmt=gbrp," ..
                "zscale=primaries=bt709:transfer=bt709:matrix=bt709:range=pc" ..
                format_suffix
        end
    end

    local prefix = quality > 1 and "gpu=api=vulkan:w=" or "scale=w="
    return prefix .. dimensions .. format_suffix
end

local function update_overlay(width, height, use_script)
    if not width or not state.show_overlay then return end

    if state.cursor_x then
        mp.command_native_async({
            name = "overlay-add",
            id = config.overlay_id,
            x = state.cursor_x,
            y = state.cursor_y,
            file = config.tnpath .. ".bgra",
            offset = 0,
            fmt = "bgra",
            w = width,
            h = height,
            stride = 4 * width
        }, function() end)
    elseif use_script then
        mp.commandv("script-message-to", use_script, "thumbfast-render",
            utils.format_json({
                width = width,
                height = height,
                x = state.cursor_x,
                y = state.cursor_y,
                socket = config.socket,
                tnpath = config.tnpath,
                overlay_id = config.overlay_id
            }))
    end
end

local function process_thumbnail_file()
    local temp_path = config.tnpath .. ".tmp"
    os.remove(temp_path)
    os.rename(config.tnpath, temp_path)

    local file_info = utils.file_info(temp_path)
    if not file_info then return false end

    state.spawn_waiting = false
    local expected_pixels = state.effective_width * state.effective_height
    local actual_pixels = file_info.size / 4

    if expected_pixels ~= actual_pixels then
        for h = state.effective_height, state.effective_height - 5, -1 do
            if actual_pixels % h == 0 then
                state.real_width = actual_pixels / h
                state.real_height = h
                break
            end
        end
    else
        state.real_width = state.effective_width
        state.real_height = state.effective_height
    end

    os.remove(config.tnpath .. ".bgra")
    os.rename(temp_path, config.tnpath .. ".bgra")

    if state.real_width ~= state.last_real_width or state.real_height ~= state.last_real_height then
        state.last_real_width, state.last_real_height = state.real_width, state.real_height
        update_info(state.real_width, state.real_height)
    end

    return true
end

local function clear_state()
    if state.file_timer then state.file_timer:kill() end
    if state.seek_timer then state.seek_timer:kill() end

    if config.quit_after_inactivity > 0 and state.activity_timer then
        state.activity_timer:kill()
        state.activity_timer:resume()
    end

    state.last_seek_time, state.show_overlay = nil, false
    state.last_cursor_x, state.last_cursor_y = nil, nil

    if not state.script_name then
        mp.command_native_async({ name = "overlay-remove", id = config.overlay_id }, function() end)
    end
end

local function spawn_thumbnail_process(seek_time)
    if state.disabled or not state.properties["path"] then return end

    if config.quit_after_inactivity > 0 then
        state.activity_timer:kill()
        state.activity_timer:resume()
    end

    local media_path = state.properties["stream-open-filename"]
    if not (media_path and state.properties["demuxer-via-network"] and state.properties["path"] ~= media_path) then
        media_path = state.properties["path"]
    end

    cleanup_files()
    state.has_video = state.properties["vid"] or 0

    local args = {
        (config.binpath == "default" and "mpv" or config.binpath),
        "--config=no", "--terminal=no", "--msg-level=all=no", "--idle=yes",
        "--keep-open=always", "--pause=yes", "--ao=null", "--osc=no",
        "--load-stats-overlay=no", "--load-console=no", "--load-commands=no",
        "--load-auto-profiles=no", "--load-select=no", "--load-positioning=no",
        "--clipboard-backends=", "--video-osd=no", "--autoload-files=no",
        "--vd-lavc-skiploopfilter=all", "--vd-lavc-skipidct=all", "--vd-lavc-fast",
        "--vd-lavc-threads=" .. config.sw_threads,
        "--hwdec=" .. config.hwdec,
        "--edition=" .. (state.properties["edition"] or "auto"),
        "--vid=" .. (state.has_video or "auto"),
        "--sub=no", "--audio=no",
        "--start=" .. seek_time,
        "--dither-depth=no", "--tone-mapping=hable", "--audio-pitch-correction=no",
        "--deinterlace=no", "--ytdl-format=worst",
        "--demuxer-readahead-secs=0", "--demuxer-max-bytes=128KiB",
        "--vf=" .. build_video_filter(),
        "--ovc=rawvideo", "--of=image2", "--ofopts=update=1",
        "--ocopy-metadata=no", "--input-ipc-server=" .. config.socket,
        "--media-controls=no", "--input-media-keys=no",
        "--o=" .. config.tnpath,
        media_path
    }

    state.spawned, state.spawn_waiting = true, true

    exec_subprocess(args, true, function(success, result)
        if state.spawn_waiting and (not success or (result.status ~= 0 and result.status ~= -2)) then
            state.spawned, state.spawn_waiting = false, false
            if not state.spawn_working then
                mp.msg.error("thumbfast 子进程创建失败")
            end
        elseif success and result.status == 0 then
            state.spawn_working, state.spawn_waiting = true, false
        end
    end)
end

local function perform_seek(is_fast)
    if not state.last_seek_time then return end

    local seek_mode = " absolute+exact"
    if config.precise == 2 then
        seek_mode = " absolute+exact"
    elseif config.precise == 1 or is_fast then
        seek_mode = " absolute+keyframes"
    end

    send_command("async seek " .. state.last_seek_time .. seek_mode)
end

state.file_timer = mp.add_periodic_timer(1 / 60, function()
    if process_thumbnail_file() then
        update_overlay(state.real_width, state.real_height, state.script_name)
    end
end)
state.file_timer:kill()

state.seek_timer = mp.add_periodic_timer(config.frequency, function()
    if state.seek_count == 0 then
        perform_seek(true)
        state.seek_count = 1
    elseif state.seek_count == 2 then
        state.seek_timer:kill()
        perform_seek(false)
    else
        state.seek_count = state.seek_count + 1
    end
end)
state.seek_timer:kill()

local function quit_on_inactivity()
    state.activity_timer:kill()
    if state.show_overlay then
        state.activity_timer:resume()
        return
    end
    send_command("quit")
    state.spawned, state.real_width, state.real_height = false, nil, nil
    clear_state()
end

state.activity_timer = mp.add_timeout(config.quit_after_inactivity, quit_on_inactivity)
state.activity_timer:kill()

local function thumb(time, cursor_x, cursor_y, script_name)
    if state.disabled then return end

    time = tonumber(time)
    if not time then return end

    state.cursor_x = cursor_x ~= "" and math.floor(cursor_x + 0.5) or nil
    state.cursor_y = cursor_y ~= "" and math.floor(cursor_y + 0.5) or nil
    state.script_name = script_name

    local pos_changed = state.last_cursor_x ~= state.cursor_x or state.last_cursor_y ~= state.cursor_y
    if pos_changed or not state.show_overlay then
        state.show_overlay = true
        state.last_cursor_x, state.last_cursor_y = state.cursor_x, state.cursor_y
        update_overlay(state.real_width, state.real_height, script_name)
    end

    if config.quit_after_inactivity > 0 then
        state.activity_timer:kill()
        state.activity_timer:resume()
    end

    if time == state.last_seek_time then return end
    state.last_seek_time = time

    if not state.spawned then
        spawn_thumbnail_process(time)
    end

    if state.seek_timer:is_enabled() then
        state.seek_count = 0
    else
        state.seek_timer:resume()
        perform_seek(true)
        state.seek_count = 1
    end

    if not state.file_timer:is_enabled() then
        state.file_timer:resume()
    end
end

local function watch_property_changes()
    if not state.dirty or not state.properties["video-params"] then return end
    state.dirty = false

    local old_w, old_h = state.effective_width, state.effective_height
    calculate_dimensions()

    local resized = old_w ~= state.effective_width or old_h ~= state.effective_height
    if resized or (state.last_has_vid ~= state.has_video and state.has_video ~= 0) then
        update_info(state.effective_width, state.effective_height)
    end

    if state.spawned and resized then
        local last_time = state.last_seek_time
        send_command("quit")
        clear_state()
        state.spawned = false
        spawn_thumbnail_process(last_time or mp.get_property_number("time-pos", 0))
        state.file_timer:resume()
    end

    state.last_has_vid = state.has_video

    if not state.spawned and not state.disabled and config.spawn_first and resized then
        spawn_thumbnail_process(mp.get_property_number("time-pos", 0))
        state.file_timer:resume()
    end
end

local function sync_property(prop_name, value)
    state.properties[prop_name] = value
    if not value then return end

    if prop_name == "vid" then
        if type(value) == "boolean" then
            state.has_video, state.last_has_video = 0, 0
            update_info(state.effective_width, state.effective_height)
            clear_state()
        else
            state.has_video = 1
        end
    end

    if type(value) == "boolean" then
        value = value and "yes" or "no"
    end

    if state.spawned then
        send_command("set " .. prop_name .. " " .. value)
        state.dirty = true
    end
end

local function on_file_loaded()
    clear_state()
    state.spawned = false
    state.real_width, state.real_height, state.last_real_width, state.last_real_height = nil, nil, nil, nil
    state.last_seek_time = nil

    calculate_dimensions()
    mp.add_timeout(0.125, function() update_info(state.effective_width, state.effective_height) end)
end

local function on_shutdown()
    send_command("quit")
    cleanup_files()
end

mp.observe_property("current-tracks/video", "native", function(_, v)
    state.properties["current-tracks/video"] = v
end)

mp.observe_property("track-list", "native", function(_, v)
    for _, track in ipairs(v) do
        if track.type == "video" and track.selected then
            state.properties["current-tracks/video"] = track
            break
        end
    end
end)

for _, prop in ipairs({ "display-hidpi-scale", "video-params", "video-dec-params" }) do
    mp.observe_property(prop, "native", function(_, v)
        state.properties[prop] = v
        state.dirty = true
    end)
end

for _, prop in ipairs({ "demuxer-via-network", "stream-open-filename", "path" }) do
    mp.observe_property(prop, "native", function(_, v) state.properties[prop] = v end)
end

mp.observe_property("vid", "native", sync_property)
mp.observe_property("edition", "native", sync_property)

mp.register_script_message("thumb", thumb)
mp.register_script_message("clear", clear_state)
mp.register_event("file-loaded", on_file_loaded)
mp.register_event("shutdown", on_shutdown)
mp.register_idle(watch_property_changes)

local function init(_, loaded)
    if not loaded then return end
    state.auto_run = not mp.get_property_native("user-data/thumbfast-off")
    state.hwdec = not mp.get_property_native("user-data/thumbfast-hw-off")
    mp.add_key_binding(nil, "thumb_restart", function()
        if not state.auto_run then return end
        clear_state()
        on_shutdown()
        on_file_loaded()
        mp.osd_message("缩略图功能已重启")
    end)
    mp.add_key_binding(nil, "thumb_toggle", function()
        state.auto_run = not state.auto_run
        clear_state()
        on_shutdown()
        on_file_loaded()
        mp.set_property_native("user-data/thumbfast-off", not state.auto_run)
        mp.osd_message("缩略图功能已" .. (state.auto_run and "启用" or "禁用"))
    end)
    mp.add_key_binding(nil, "thumb_hwdec_toggle", function()
        state.hwdec = not state.hwdec
        mp.set_property_native("user-data/thumbfast-hw-off", not state.hwdec)
        mp.osd_message("缩略图硬件解码已" .. (state.hwdec and "启用" or "禁用"))
        clear_state()
        on_shutdown()
        on_file_loaded()
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
