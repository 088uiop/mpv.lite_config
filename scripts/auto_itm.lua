local mp = require 'mp'

local itm = "auto"
local itm_state = nil

local function update()
    if Lock then return end
    Lock = mp.add_timeout(0.2, function() Lock = nil end)
    local vp = mp.get_property_native("video-params")
    local vtp = mp.get_property_native("video-target-params")
    if not vp or not vtp then return end
    local sdr_to_hdr = vp.gamma ~= 'pq' and vtp.gamma == 'pq'
    itm_state = itm == "auto" and sdr_to_hdr or itm == "yes"
    mp.set_property_native("inverse-tone-mapping", itm_state)
    mp.set_property_native("tone-mapping", itm_state and "bt.2446a" or "auto")
    mp.commandv("script-message", "use_itm_shaders", (itm_state and sdr_to_hdr) and "true" or "false")
end

mp.add_timeout(0.1, function()
    if mp.get_property_native("user-data/itm") then
        itm = mp.get_property_native("user-data/itm")
    end
    mp.set_property_native("user-data/itm", itm)
    mp.observe_property("inverse-tone-mapping", nil, update)
    mp.observe_property("video-params", nil, update)
    mp.observe_property("video-target-params", nil, update)
    update()
end)

mp.register_script_message("set_itm", function(state)
    itm = state ~= "next" and state or (itm == "auto" and "no") or (itm == "no" and "yes") or "auto"
    mp.set_property_native("user-data/itm", itm)
    mp.osd_message("inverse-tone-mapping: " .. itm)
    update()
end)
