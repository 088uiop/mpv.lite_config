local mp = require 'mp'
local utils = require 'mp.utils'
local options = require 'mp.options'

local o = {
    save_and_load = true,
    props = "",
    user_props = ""
}

options.read_options(o)

local function split(inputstr, sep)
    local result = {}
    for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
        table.insert(result, str)
    end
    return result
end

local config_dir = mp.command_native({ "expand-path", "~~/" })
local props = split(o.props, ',')
for _, v in ipairs(split(o.user_props, ',')) do
    table.insert(props, "user-data/" .. v)
end

local function save_state()
    if not o.save_and_load then return end
    local state = {}
    for _, prop in ipairs(props) do
        state[prop] = mp.get_property_native(prop)
    end
    local file = io.open(config_dir .. "/settings_state.json", "w")
    if file then
        local json = utils.format_json(state)
        if json then file:write(json) end
        file:close()
    end
end

local function load_state()
    if not o.save_and_load then return end
    local file = io.open(config_dir .. "/settings_state.json", "r")
    if not file then return end
    local ok, saved = pcall(utils.parse_json, file:read("*a"))
    file:close()
    if not (ok and saved) then return end
    for _, prop in ipairs(props) do
        if saved[prop] ~= nil then mp.set_property_native(prop, saved[prop]) end
    end
end

load_state()
mp.register_script_message("save_state", save_state)
mp.register_event("shutdown", save_state)
