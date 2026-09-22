local mp = require 'mp'
local utils = require 'mp.utils'

local itm = {
    state = 'auto',
    target_peak = '600',
    reference_white = '203',
    shader_options = {
        luma_boost = '0.5',
        chroma_boost = '0.5'
    }
}
local menu_data = {}

local function update()
    local use_itm = itm.state == 'auto' and (VOP_GAMMA ~= 'pq' and VTP_GAMMA == 'pq') or itm.state == 'yes'
    mp.set_property_native('user-data/itm', itm)
    mp.set_property_native('inverse-tone-mapping', use_itm)
    mp.set_property_native('tone-mapping', use_itm and 'bt.2446a' or 'auto')
    mp.set_property_native('hdr-reference-white', use_itm and itm.reference_white or 'auto')
    mp.set_property_native('target-peak', use_itm and itm.target_peak or 'auto')
    mp.set_property_native('glsl-shader-opts', itm.shader_options)
    mp.commandv('script-message-to', 'shader', 'use_itm_shader', use_itm and 'true' or 'false')
    mp.commandv('script-message-to', 'shader', 'refresh_shaders')
end

local function show_menu()
    menu_data = {
        type = 'itm_menu',
        title = 'ITM 设置',
        callback = { mp.get_script_name(), 'update_itm_menu' },
        items = {
            { title = '状态', value = 'auto/no/yes', hint = itm.state },
            { title = '目标亮度', value = '整数 (范围: 10~10000) 或 auto', hint = itm.target_peak },
            { title = '参考白', value = '整数 (范围: 10~10000) 或 auto', hint = itm.reference_white },
            { title = '暗部增强', value = '小数 (范围: 0.0~1.0)', hint = tostring(itm.shader_options.luma_boost) },
            { title = '饱和度增强', value = '小数 (范围: 0.0~1.0)', hint = tostring(itm.shader_options.chroma_boost) }
        }
    }
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data))
end

local function set_itm(key, value)
    itm[key] = value
    update()
end

local function toggle_itm(state, no_osd)
    itm.state = state or ({ auto = 'no', no = 'yes', yes = 'auto' })[itm.state]
    if not no_osd then mp.osd_message('inverse-tone-mapping: ' .. itm.state) end
    update()
end

local function init(_, loaded)
    if not loaded then return end
    local saved = mp.get_property_native('user-data/itm')
    if saved then
        itm = saved
    else
        mp.set_property_native('user-data/itm', itm)
    end
    mp.observe_property('video-out-params', 'native', function(_, vop)
        if not vop or VOP_GAMMA == vop.gamma then return end
        VOP_GAMMA = vop.gamma
        update()
    end)
    mp.observe_property('video-target-params', 'native', function(_, vtp)
        if not vtp or VTP_GAMMA == vtp.gamma then return end
        VTP_GAMMA = vtp.gamma
        update()
    end)
    mp.register_script_message('update_itm_menu', function(json)
        local event = utils.parse_json(json)
        if event.type == 'activate' then
            menu_data.search_debounce = 'submit'
            menu_data.search_style = 'palette'
            menu_data.on_search = 'callback'
            menu_data.title = event.value
            if event.index == 1 then
                toggle_itm(nil, true)
                menu_data.items[1].hint = itm.state
            end
            for _, item in ipairs(menu_data.items) do item.active = false end
            menu_data.items[event.index].active = true
            mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu_data))
        elseif event.type == 'search' then
            for index, item in ipairs(menu_data.items) do
                if item.active then
                    local invaild = false
                    if index == 1 then
                        if ({ auto = true, no = true, yes = true })[event.query] then
                            set_itm('state', event.query)
                        else
                            invaild = true
                        end
                    elseif index <= 3 then
                        local value = tonumber(event.query)
                        if event.query == 'auto' or value and value % 1 == 0 and value >= 10 and value <= 10000 then
                            set_itm(index == 2 and 'target_peak' or 'reference_white', event.query)
                        else
                            invaild = true
                        end
                    else
                        local value = tonumber(event.query)
                        if value and value >= 0 and value <= 1 then
                            set_itm('shader_options',
                                {
                                    luma_boost = index == 4 and event.query or itm.shader_options.luma_boost,
                                    chroma_boost = index == 5 and event.query or itm.shader_options.chroma_boost
                                })
                        else
                            invaild = true
                        end
                    end
                    if invaild then
                        menu_data.title = '输入值无效'
                        mp.add_timeout(1, function()
                            menu_data.title = item.value
                            mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(menu_data))
                        end)
                    else
                        item.hint = event.query
                    end
                    break
                end
            end
            mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menu_data))
        end
    end)
    mp.register_script_message('toggle_itm', toggle_itm)
    mp.register_script_message('show_itm_menu', show_menu)
    mp.unobserve_property(init)
end

mp.observe_property('user-data/__state_loaded__', 'bool', init)
