local mp = require 'mp'


local states = {
    nvidia_vsr = false,
    intel_vsr = false,
    nvidia_hdr = false
}

local hw_filters = {
    nvidia_vsr = {
        label = "NVIDIA-VSR",
        vendor = "nvidia",
        params = "!d3d11vpp=format=nv12:scale=2:scaling-mode=nvidia"
    },
    intel_vsr = {
        label = "INTEL-VSR",
        vendor = "intel",
        params = "!d3d11vpp=format=nv12:scale=2:scaling-mode=intel"
    },
    nvidia_hdr = {
        label = "NVIDIA-HDR",
        vendor = "nvidia",
        params = "d3d11vpp=nvidia-true-hdr=yes"
    }
}

local vid = 1
local gpu_vendor = nil
local gpu_context = nil

local function vsr_check()
    local w = mp.get_property_native("width")
    local h = mp.get_property_native("height")
    if not w or not h then return end
    for id, filter in pairs(hw_filters) do
        if id:find("vsr") and states[id] then
            local enable = true
            if id == "nvidia_vsr" then
                enable = w >= 540 and h >= 320 and w <= 2560 and h <= 1440
            elseif id == "intel_vsr" then
                enable = w >= 540 and h >= 320 and w <= 1920 and h <= 1080
            end
            if not enable then mp.msg.warn(filter.label .. ": 输入分辨率超出作用阈值") end
            for _, v in ipairs(mp.get_property_native("vf")) do
                if v.label == filter.label and v.enabled ~= enable then
                    mp.commandv("vf", "toggle", "@" .. filter.label)
                    return
                end
            end
        end
    end
end

local function gpu_context_check()
    gpu_context = mp.get_property_native("current-gpu-context")
    if not gpu_context then
        mp.add_timeout(0.2, gpu_context_check)
        return
    end
    if gpu_context == "d3d11" then return end
    for id, filter in pairs(hw_filters) do
        if states[id] then
            states[id] = false
            mp.commandv("vf", "remove", "@" .. filter.label)
        end
    end
    mp.set_property_native("user-data/hw-filter", states)
    mp.set_property_native("vid", vid)
end

local function toggle_hw_filter(id)
    if gpu_context ~= "d3d11" or gpu_vendor ~= hw_filters[id].vendor then return end
    states[id] = not states[id]
    mp.set_property_native("user-data/hw-filter", states)
    mp.osd_message(hw_filters[id].label .. ": " .. (states[id] and "开" or "关"))
    if states[id] then
        mp.commandv("vf", id:find("vsr") and "pre" or "add", "@" .. hw_filters[id].label .. ":" .. hw_filters[id].params)
    else
        mp.commandv("vf", "remove", "@" .. hw_filters[id].label)
    end
    vsr_check()
end

local function init(_, loaded)
    if not loaded then return end
    local function detect_gpu(event)
        local t = event.text or ""
        local name = t:match("Device Name:%s*([^\n]+)") or ""
        local device_id = t:match("Device ID:%s*(%x%x%x%x):")
        if not device_id then return end
        local n = name:lower()
        if device_id:lower() == "10de" or n:find("nvidia", 1, true) or n:find("rtx", 1, true) then
            gpu_vendor = "nvidia"
        elseif device_id:lower() == "8086" or n:find("intel", 1, true) or n:find("arc", 1, true) then
            gpu_vendor = "intel"
        else
            gpu_vendor = "other"
        end
        mp.set_property_native("user-data/gpu-vendor", gpu_vendor)
        for id, filter in pairs(hw_filters) do
            if states[id] and gpu_vendor == filter.vendor then
                mp.commandv("vf", id:find("vsr") and "pre" or "add", "@" .. filter.label .. ":" .. filter.params)
            end
        end
        mp.unregister_event(detect_gpu)
        mp.enable_messages("no")
    end
    mp.enable_messages("v")
    local saved = mp.get_property_native("user-data/hw-filter")
    if saved then
        states = saved
    else
        mp.set_property_native("user-data/hw-filter", states)
    end
    mp.observe_property("vid", "native", function() vid = mp.get_property_native("vid") or vid end)
    mp.observe_property("gpu-api", "native", gpu_context_check)
    mp.register_event("file-loaded", vsr_check)
    mp.register_event("log-message", detect_gpu)
    mp.register_script_message("toggle_hw_filter", toggle_hw_filter)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
