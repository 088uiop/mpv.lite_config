local mp = require 'mp'

local itm = {
    state = "auto",
    optimization = true,
}

local function update()
    mp.set_property_native("user-data/itm", itm)
    local hdr_video = VP_GAMMA == 'pq'
    local hdr_display = VTP_GAMMA == 'pq'
    local sdr_to_hdr = not hdr_video and hdr_display
    local use_itm = itm.state == "auto" and sdr_to_hdr or itm.state == "yes"
    local use_itm_shaders = itm.optimization and use_itm and sdr_to_hdr
    mp.set_property_native("inverse-tone-mapping", use_itm)
    mp.set_property_native("tone-mapping", use_itm and "bt.2446a" or "auto")
    mp.commandv("script-message", "use_itm_shader", use_itm_shaders and "true" or "false")
end

local function init(_, loaded)
    if not loaded then return end
    local saved = mp.get_property_native("user-data/itm")
    if saved then
        itm = saved
    else
        mp.set_property_native("user-data/itm", itm)
    end
    mp.observe_property("video-params", "native", function(_, vp)
        if not vp or VP_GAMMA == vp.gamma then return end
        VP_GAMMA = vp.gamma
        update()
    end)
    mp.observe_property("video-target-params", "native", function(_, vtp)
        if not vtp or VTP_GAMMA == vtp.gamma then return end
        VTP_GAMMA = vtp.gamma
        update()
    end)
    mp.register_script_message("set_itm", function(state)
        itm.state = state == "next" and ({ auto = "no", no = "yes", yes = "auto" })[itm.state] or state
        mp.osd_message("inverse-tone-mapping: " .. itm.state)
        update()
    end)
    mp.register_script_message("toggle_itm_optimization", function()
        itm.optimization = not itm.optimization
        update()
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
