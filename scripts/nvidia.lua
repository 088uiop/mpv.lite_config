local mp = require 'mp'

local vid = 1
local vsr = false
local hdr = false
local init_check = true

local function toggle_vsr(s)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label == 'NVvsr' and filter.enabled ~= s then
            mp.commandv("vf", "toggle", "@NVvsr")
            return
        end
    end
end

local function vsr_check()
    local w = mp.get_property_native("width")
    local h = mp.get_property_native("height")
    if not (w and h) then return end
    if w < 540 or h < 320 or w > 2560 or h > 1440 then
        mp.msg.warn("NV-VSR: 输入分辨率超出作用阈值")
    else
        toggle_vsr(true)
    end
end

local function gpu_context_check()
    if init_check then
        init_check = false
        return
    end
    if mp.get_property_native("current-gpu-context") ~= 'd3d11' then
        if vsr then
            vsr = false
            mp.commandv("vf", "remove", "@NVvsr")
            mp.set_property_native("user-data/nv-vsr", vsr)
        end
        if hdr then
            hdr = false
            mp.commandv("vf", "remove", "@NVhdr")
            mp.set_property_native("user-data/nv-hdr", hdr)
        end
        mp.set_property_native("vid", vid)
    end
end

local function init(_, loaded)
    if not loaded then return end
    if mp.get_property_native("user-data/nv-vsr") then
        vsr = true
        mp.commandv("vf", "pre", "@NVvsr:!d3d11vpp=format=nv12:scale=2:scaling-mode=nvidia")
    end
    if mp.get_property_native("user-data/nv-hdr") then
        hdr = true
        mp.commandv("vf", "add", "@NVhdr:d3d11vpp=nvidia-true-hdr")
    end
    mp.observe_property("vid", "native", function() vid = mp.get_property_native("vid") or vid end)
    mp.observe_property("gpu-api", "native", gpu_context_check)
    mp.register_event("file-loaded", function()
        if not vsr then return end
        toggle_vsr(false)
        vsr_check()
    end)
    mp.add_key_binding(nil, "toggle-nv-vsr", function()
        if mp.get_property_native("current-gpu-context") ~= 'd3d11' then return end
        vsr = not vsr
        mp.set_property_native("user-data/nv-vsr", vsr)
        mp.osd_message("NV-VSR: " .. (vsr and "开" or "关"))
        if vsr then
            mp.commandv("vf", "pre", "@NVvsr:!d3d11vpp=format=nv12:scale=2:scaling-mode=nvidia")
            vsr_check()
        else
            mp.commandv("vf", "remove", "@NVvsr")
        end
    end)
    mp.add_key_binding(nil, "toggle-nv-hdr", function()
        if mp.get_property_native("current-gpu-context") ~= 'd3d11' then return end
        hdr = not hdr
        mp.set_property_native("user-data/nv-hdr", hdr)
        mp.osd_message("NV-HDR: " .. (hdr and "开" or "关"))
        if hdr then
            mp.commandv("vf", "add", "@NVhdr:d3d11vpp=nvidia-true-hdr")
        else
            mp.commandv("vf", "remove", "@NVhdr")
        end
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
