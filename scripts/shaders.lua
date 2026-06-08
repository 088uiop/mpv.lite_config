local mp = require 'mp'

local shaders = {
    state = "nil",
    anime4k = { quality = "_M", mode = "", order = "_RU" },
    cunny = { quality = "-3x12", mode = "-DS", dp4a = "" },
    fsrcnnx = { quality = "_8_0_4_1" },
    nnedi3 = { quality = "_nns32" },
    ravu = { quality = "_r2" }
}

local itm = false

local function update_shaders(no_osd)
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
                path .. "Anime4K" .. shaders.anime4k.order .. shaders.anime4k.mode .. shaders.anime4k.quality .. ".glsl",
                path .. "Anime4K" .. shaders.anime4k.order .. shaders.anime4k.mode .. shaders.anime4k.quality .. ".glsl",
                path .. "Anime4K_AutoScalePost.glsl"
            }
        elseif shaders.state == "CuNNy" then
            glsl_shaders = {
                path .. "CuNNy" .. shaders.cunny.quality .. shaders.cunny.mode .. shaders.cunny.dp4a .. ".glsl",
                path .. "CuNNy" .. shaders.cunny.quality .. shaders.cunny.mode .. shaders.cunny.dp4a .. ".glsl"
            }
        elseif shaders.state == "FSRCNNX" then
            glsl_shaders = {
                path .. "FSRCNNX_x2" .. shaders.fsrcnnx.quality .. ".glsl",
                path .. "FSRCNNX_x2" .. shaders.fsrcnnx.quality .. ".glsl"
            }
        elseif shaders.state == "NNEDI3" then
            glsl_shaders = {
                path .. "nnedi3" .. shaders.nnedi3.quality .. "_win8x4.glsl",
                path .. "nnedi3" .. shaders.nnedi3.quality .. "_win8x4.glsl"
            }
        elseif shaders.state == "RAVU" then
            glsl_shaders = {
                path .. "ravu" .. shaders.ravu.quality .. ".glsl",
                path .. "ravu" .. shaders.ravu.quality .. ".glsl"
            }
        end
    end
    if itm then glsl_shaders[#glsl_shaders + 1] = "~~/shaders/ITM_Optimization.glsl" end
    mp.set_property_native("glsl-shaders", glsl_shaders)
    if no_osd then return end
    mp.osd_message("着色器: " .. shaders.state)
end

mp.add_timeout(0.1, function()
    local saved = mp.get_property_native("user-data/shaders")
    if saved then shaders = saved end
    update_shaders(true)
    mp.register_script_message("set_shaders", function(shader, key, value)
        shaders[shader][key] = value
        update_shaders(true)
    end)
    mp.register_script_message("use_shader", function(shader)
        shaders.state = shader
        update_shaders()
    end)
    mp.register_script_message("use_itm_shaders", function(state)
        itm = state == "true"
        update_shaders(true)
    end)
end)
