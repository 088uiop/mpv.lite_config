local mp = require 'mp'

local vid = 1
local mtmtg = false
local init_check = true

-- user-data/gpu-moorethread 为 nil（未检测）时放行，仅 false（确认不存在）时拦截
local function vendor_ok()
    return mp.get_property_native("user-data/gpu-moorethread") ~= false
end

local function toggle_mtmtg(s)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label == 'MTVSR' and filter.enabled ~= s then
            mp.commandv("vf", "toggle", "@MTVSR")
            return
        end
    end
end

local function mtmtg_check()
    local w = mp.get_property_native("width")
    local h = mp.get_property_native("height")
    if not (w and h) then return end
    if w < 540 or h < 320 or w > 2560 or h > 1440 then
        mp.msg.warn("MT-VSR: 输入分辨率超出作用阈值")
    else
        toggle_mtmtg(true)
    end
end

local function gpu_context_check()
    if init_check then
        init_check = false
        return
    end
    if mp.get_property_native("current-gpu-context") ~= 'd3d11' or not vendor_ok() then
        if mtmtg then
            mtmtg = false
            mp.commandv("vf", "remove", "@MTVSR")
            mp.set_property_native("user-data/mtmtg-vsr", mtmtg)
        end
        mp.set_property_native("vid", vid)
    end
end

local function init(_, loaded)
    if not loaded then return end
    if mp.get_property_native("user-data/mtmtg-vsr") then
        if vendor_ok() then
            mtmtg = true
            mp.commandv("vf", "pre", "@MTVSR:!d3d11vpp=format=nv12:scale=2:scaling-mode=mtmtg")
        else
            mp.set_property_native("user-data/mtmtg-vsr", false)
        end
    end
    mp.observe_property("vid", "native", function() vid = mp.get_property_native("vid") or vid end)
    mp.observe_property("gpu-api", "native", gpu_context_check)
    local vendor_init = true
    mp.observe_property("user-data/gpu-moorethread", "native", function()
        if vendor_init then
            vendor_init = false
            return
        end
        gpu_context_check()
    end)
    mp.register_event("file-loaded", function()
        if not mtmtg then return end
        toggle_mtmtg(false)
        mtmtg_check()
    end)
    mp.add_key_binding(nil, "toggle-mtmtg-vsr", function()
        if mp.get_property_native("current-gpu-context") ~= 'd3d11' then return end
        if not vendor_ok() then
            mp.osd_message("MT-VSR: 未检测到摩尔线程显卡，无法启用")
            return
        end
        mtmtg = not mtmtg
        mp.set_property_native("user-data/mtmtg-vsr", mtmtg)
        mp.osd_message("MT-VSR: " .. (mtmtg and "开" or "关"))
        if mtmtg then
            mp.commandv("vf", "pre", "@MTVSR:!d3d11vpp=format=nv12:scale=2:scaling-mode=mtmtg")
            mtmtg_check()
        else
            mp.commandv("vf", "remove", "@MTVSR")
        end
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
