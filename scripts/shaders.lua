local mp = require 'mp'

local shaders = {
    state = "nil",
    anime4k = { quality = "_M", mode = "", order = "_RU" },
    cunny = { quality = "-3x12", mode = "-DS", dp4a = "" },
    fsrcnnx = { quality = "_8_0_4_1" },
    nnedi3 = { quality = "_nns32" },
    ravu = { quality = "_r2" },
    gf = false,
    itm = false
}

local function update(no_osd)
    mp.set_property_native("user-data/shaders", shaders)
    local glsl_shaders = {}
    if shaders.state ~= "nil" then
        local path = "~~/shaders/" .. shaders.state .. "/"
        if shaders.state == "Adaptive_sharpen" then
            glsl_shaders = {
                path .. "Adaptive_sharpen_lite_RT.glsl"
            }
        elseif shaders.state == "Anime4K" then
            glsl_shaders = {
                path .. "Anime4K" .. shaders.anime4k.order .. shaders.anime4k.mode .. shaders.anime4k.quality .. ".glsl"
            }
        elseif shaders.state == "CuNNy" then
            glsl_shaders = {
                path .. "CuNNy" .. shaders.cunny.quality .. shaders.cunny.mode .. shaders.cunny.dp4a .. ".glsl"
            }
        elseif shaders.state == "FSRCNNX" then
            glsl_shaders = {
                path .. "FSRCNNX_x2" .. shaders.fsrcnnx.quality .. ".glsl"
            }
        elseif shaders.state == "NNEDI3" then
            glsl_shaders = {
                path .. "nnedi3" .. shaders.nnedi3.quality .. "_win8x4.glsl"
            }
        elseif shaders.state == "RAVU" then
            glsl_shaders = {
                path .. "ravu" .. shaders.ravu.quality .. ".glsl"
            }
        end
    end
    if shaders.gf then table.insert(glsl_shaders, "~~/shaders/kGrainFactory_RT.glsl") end
    if shaders.itm then table.insert(glsl_shaders, "~~/shaders/ITM_Optimization.glsl") end
    mp.set_property_native("glsl-shaders", glsl_shaders)
    if no_osd then return end
    mp.osd_message("着色器: " .. shaders.state)
end

local function init(_, loaded)
    if not loaded then return end
    local saved = mp.get_property_native("user-data/shaders")
    if saved then shaders = saved end
    update(true)
    mp.register_script_message("set_shaders", function(shader, key, value)
        shaders[shader][key] = value
        update(true)
    end)
    mp.register_script_message("use_shader", function(shader)
        shaders.state = shader
        update()
    end)
    mp.register_script_message("toggle_gf_shader", function()
        shaders.gf = not shaders.gf
        update(true)
    end)
    mp.register_script_message("use_itm_shader", function(state)
        if shaders.itm == (state == "true") then return end
        shaders.itm = not shaders.itm
        update(true)
    end)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
