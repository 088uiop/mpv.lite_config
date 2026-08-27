local mp = require 'mp'

local vid = 1
local vsr = false
local init_check = true

-- user-data/gpu-intel 为 nil（未检测）时放行，仅 false（确认不存在）时拦截
local function vendor_ok()
    return mp.get_property_native("user-data/gpu-intel") ~= false
end

local function toggle_vsr(s)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label == 'IntelVSR' and filter.enabled ~= s then
            mp.commandv("vf", "toggle", "@IntelVSR")
            return
        end
    end
end

local function vsr_check()
    local w = mp.get_property_native("width")
    local h = mp.get_property_native("height")
    if not (w and h) then return end
    if w < 540 or h < 320 or w > 2560 or h > 1440 then
        mp.msg.warn("INTEL-VSR: 输入分辨率超出作用阈值")
    else
        toggle_vsr(true)
    end
end

local function gpu_context_check()
    if init_check then
        init_check = false
        return
    end
    if mp.get_property_native("current-gpu-context") ~= 'd3d11' or not vendor_ok() then
        if vsr then
            vsr = false
            mp.commandv("vf", "remove", "@IntelVSR")
            mp.set_property_native("user-data/intel-vsr", vsr)
        end
        mp.set_property_native("vid", vid)
    end
end

local function init(_, loaded)
    if not loaded then return end
    if mp.get_property_native("user-data/intel-vsr") then
        if vendor_ok() then
            vsr = true
            mp.commandv("vf", "pre", "@IntelVSR:!d3d11vpp=format=nv12:scale=2:scaling-mode=intel")
        else
            mp.set_property_native("user-data/intel-vsr", false)
        end
    end
    mp.observe_property("vid", "native", function() vid = mp.get_property_native("vid") or vid end)
    mp.observe_property("gpu-api", "native", gpu_context_check)
    local vendor_init = true
    mp.observe_property("user-data/gpu-intel", "native", function()
        if vendor_init then
            vendor_init = false
            return
        end
        gpu_context_check()
    end)
    mp.register_event("file-loaded", function()
        if not vsr then return end
        toggle_vsr(false)
        vsr_check()
    end)
    mp.add_key_binding(nil, "toggle-intel-vsr", function()
        if mp.get_property_native("current-gpu-context") ~= 'd3d11' then return end
        if not vendor_ok() then
            mp.osd_message("INTEL-VSR: 未检测到 Intel 显卡，无法启用")
            return
        end
        vsr = not vsr
        mp.set_property_native("user-data/intel-vsr", vsr)
        mp.osd_message("INTEL-VSR: " .. (vsr and "开" or "关"))
        if vsr then
            mp.commandv("vf", "pre", "@IntelVSR:!d3d11vpp=format=nv12:scale=2:scaling-mode=intel")
            vsr_check()
        else
            mp.commandv("vf", "remove", "@IntelVSR")
        end
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
