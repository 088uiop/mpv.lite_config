local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    save_and_load = true,
    props = "",
    user_props = ""
}

options.read_options(o)

mp.set_property_native("user-data/__state_loaded__", false)
if o.save_and_load then
    local function split(inputstr, sep)
        local result = {}
        for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
            table.insert(result, str)
        end
        return result
    end
    local config_dir = mp.command_native({ "expand-path", "~~/" })
    local state = {}
    local props = split(o.props, ',')
    for _, v in ipairs(split(o.user_props, ',')) do
        table.insert(props, "user-data/" .. v)
    end
    local function save(key, value)
        state[key] = value
        local file = io.open(config_dir .. "/settings_state.json", "w")
        if file then
            local json = utils.format_json(state)
            if json then file:write(json) end
            file:close()
        end
    end
    for _, prop in ipairs(props) do
        mp.observe_property(prop, "native", save)
    end
    local file = io.open(config_dir .. "/settings_state.json", "r")
    if file then
        local ok, saved = pcall(utils.parse_json, file:read("*a"))
        file:close()
        if ok and saved then
            for _, prop in ipairs(props) do
                if saved[prop] then mp.set_property_native(prop, saved[prop]) end
                state[prop] = saved[prop]
            end
        end
    end
end
mp.set_property_native("user-data/__state_loaded__", true)
