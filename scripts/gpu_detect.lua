local mp = require 'mp'
local msg = require 'mp.msg'

-- GPU 厂商检测：供 NV-VSR / Intel VSR / MT-VSR / NV-HDR 菜单项按厂商置灰
-- 主途径：捕获 mpv 创建 D3D11 设备时的 verbose 日志（Device Name / Device ID 行），
--         反映 mpv 实际使用的适配器；gpu-api、d3d11-adapter 变化导致 VO 重建时会自动更新
-- 兜底：gpu 上下文已是 d3d11 却迟迟捕获不到日志时，用 PowerShell 枚举系统显示适配器
-- 结果属性：user-data/gpu-vendor（'nvidia' / 'intel' / 'moorethread' / 'other'）
--           user-data/gpu-name（适配器描述）
--           user-data/gpu-nvidia / gpu-intel / gpu-moorethread
-- 语义：nil（未知或检测失败）= 菜单项维持可选；false = 确认不存在，置灰

local VENDORS = { "nvidia", "intel", "moorethread" }

local ID2VENDOR = {
    ["10de"] = "nvidia",
    ["8086"] = "intel",
    ["1ed5"] = "moorethread",
    ["1002"] = "other",
    ["1414"] = "other",
}

local function vendor_from_name(name)
    local n = name:lower()
    if n:find("moore threads", 1, true) or n:find("mtt", 1, true) then
        return "moorethread"
    elseif n:find("nvidia", 1, true) or n:find("geforce", 1, true)
        or n:find("quadro", 1, true) or n:find("rtx", 1, true) then
        return "nvidia"
    elseif n:find("intel", 1, true) or n:find("arc", 1, true)
        or n:find("iris", 1, true) or n:find("uhd", 1, true) then
        return "intel"
    end
end

local gpu_name = nil
local detected = false
local applied_key = nil

local function apply(found, primary, name)
    local key = primary .. "|" .. (name or "")
    for _, v in ipairs(VENDORS) do
        if found[v] then key = key .. "|" .. v end
    end
    if key == applied_key then return end
    applied_key = key
    if name then mp.set_property_native("user-data/gpu-name", name) end
    mp.set_property_native("user-data/gpu-vendor", primary)
    for _, v in ipairs(VENDORS) do
        mp.set_property_native("user-data/gpu-" .. v, found[v] == true)
    end
    if not detected then
        detected = true
        msg.info(string.format("GPU 检测完成: %s（%s）", primary, name or "未知型号"))
    end
end

mp.enable_messages("v")
mp.register_event("log-message", function(e)
    if e.prefix == mp.get_script_name() then return end
    local text = e.text or ""
    local name = text:match("Device Name:%s*([^\n]+)")
    if name then gpu_name = name:gsub("%s+$", "") end
    local vid = text:match("Device ID:%s*(%x%x%x%x):")
    if not vid then return end
    local vendor = ID2VENDOR[vid:lower()]
        or (gpu_name and vendor_from_name(gpu_name))
    if vendor then
        apply({ [vendor] = true }, vendor, gpu_name)
    end
end)

local fallback_scheduled = false

local function schedule_fallback()
    if fallback_scheduled then return end
    fallback_scheduled = true
    mp.add_timeout(1.5, function()
        if detected then return end
        msg.warn("未捕获到 D3D11 适配器日志，改用 PowerShell 枚举显示适配器")
        mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            capture_stdout = true,
            args = { "powershell", "-NoProfile", "-Command",
                "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;"
                .. "Get-CimInstance Win32_VideoController |"
                .. "ForEach-Object { $_.Name + '|' + $_.PNPDeviceID }" },
        }, function(_, result)
            if detected then return end
            if not result or result.status ~= 0 then
                msg.warn("GPU 厂商兜底检测失败，VSR/HDR 菜单项维持可选")
                return
            end
            local found, primary, primary_name = {}, nil, nil
            for line in (result.stdout or ""):gmatch("[^\r\n]+") do
                local cname, pnp = line:match("^(.-)%|(.+)$")
                if cname and pnp then
                    local vid = pnp:match("VEN_(%x+)")
                    local vendor = (vid and ID2VENDOR[vid:lower()])
                        or vendor_from_name(cname)
                    if vendor then
                        found[vendor] = true
                        if not primary then
                            primary, primary_name = vendor, cname
                        end
                    end
                end
            end
            if not primary then
                msg.warn("GPU 厂商兜底检测无有效结果，VSR/HDR 菜单项维持可选")
                return
            end
            apply(found, primary, primary_name)
        end)
    end)
end

mp.observe_property("current-gpu-context", "native", function(_, ctx)
    if ctx == "d3d11" then schedule_fallback() end
end)
if mp.get_property_native("current-gpu-context") == "d3d11" then
    schedule_fallback()
end
