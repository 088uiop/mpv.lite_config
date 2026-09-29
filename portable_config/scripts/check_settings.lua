local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    save_and_load = true,
    props = '',
    user_props = ''
}
options.read_options(o)

mp.set_property_native('user-data/__state_loaded__', false)
if o.save_and_load then
    local props = {}
    for str in string.gmatch(o.props, '([^,]+)') do props[#props + 1] = str end
    for str in string.gmatch(o.user_props, '([^,]+)') do props[#props + 1] = 'user-data/' .. str end
    local state = {}
    local path = mp.command_native({ 'expand-path', '~~/settings_state.json' })
    local function save(key, value)
        state[key] = value
        local file = io.open(path, 'w')
        if file then
            local json = utils.format_json(state)
            if json then file:write(json) end
            file:close()
        end
    end
    for _, prop in ipairs(props) do mp.observe_property(prop, 'native', save) end
    local file = io.open(path, 'r')
    if file then
        local saved = utils.parse_json(file:read('*a'))
        file:close()
        if saved then
            for _, prop in ipairs(props) do
                if saved[prop] ~= nil then mp.set_property_native(prop, saved[prop]) end
                state[prop] = saved[prop]
            end
        end
    end
end
mp.set_property_native('user-data/__state_loaded__', true)
