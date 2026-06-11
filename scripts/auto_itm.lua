local mp = require 'mp'

local itm = {
    state = "auto",
    enabled = false,
    optimization = true
}

local function update()
    if Lock then return end
    Lock = mp.add_timeout(0.2, function() Lock = nil end)
    local vp = mp.get_property_native("video-params")
    local vtp = mp.get_property_native("video-target-params")
    if not vp or not vtp then return end
    local sdr_to_hdr = vp.gamma ~= 'pq' and vtp.gamma == 'pq'
    itm.enabled = itm.state == "auto" and sdr_to_hdr or itm.state == "yes"
    mp.set_property_native("inverse-tone-mapping", itm.enabled)
    mp.set_property_native("tone-mapping", itm.enabled and "bt.2446a" or "auto")
    local use_itm_shaders = itm.optimization and itm.enabled and sdr_to_hdr
    mp.commandv("script-message", "use_itm_shader", use_itm_shaders and "true" or "false")
end

mp.add_timeout(0.1, function()
    local saved = mp.get_property_native("user-data/itm")
    if saved then
        itm = saved
    else
        mp.set_property_native("user-data/itm", itm)
    end
    mp.observe_property("inverse-tone-mapping", nil, update)
    mp.observe_property("video-params", nil, update)
    mp.observe_property("video-target-params", nil, update)
    update()
end)

mp.register_script_message("set_itm", function(state)
    itm.state = state == "next" and ({ auto = "no", no = "yes", yes = "auto" })[itm.state] or state
    mp.set_property_native("user-data/itm", itm)
    mp.osd_message("inverse-tone-mapping: " .. itm.state)
    update()
end)

mp.register_script_message("toggle_itm_optimization", function()
    itm.optimization = not itm.optimization
    mp.set_property_native("user-data/itm", itm)
    mp.osd_message("HDR逆色调映射-色彩优化: " .. (itm.optimization and "开" or "关"))
    update()
end)
