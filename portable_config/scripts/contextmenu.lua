local mp = require 'mp'

local is_init = -1
local state_tree = {}

local function compile_expr(expr)
    if not expr or expr == '' then return nil end
    local fun, err = load('return (' .. expr .. ')', 'menu-expr', 't',
        { p = setmetatable({}, { __index = function(_, k) return mp.get_property_native(k) end }) })
    if err then
        mp.msg.error('Compile error: ' .. err)
        return nil
    end
    return fun
end

local function parse_menu()
    local path = mp.command_native({ 'expand-path', '~~/contextmenu.conf' })
    local f = io.open(path, 'rb')
    if not f then return {} end
    local content = f:read('*all')
    f:close()
    local root = {}
    local stack = { { indent = -1, node = root } }
    for raw in content:gmatch('[^\r\n]+') do
        local indent_str, line = raw:match('^(%s*)(.*)$')
        local indent = #indent_str
        line = line:match('^(.-)%s*$')
        if line ~= '' and not line:match('^##') then
            while #stack > 1 and indent <= stack[#stack].indent do table.remove(stack) end
            if line:match('^#%$') then
                stack[#stack].node[#stack[#stack].node + 1] = { type = 'separator' }
            else
                local title = line:match('^#%s*(.-)%s*#!') or line:match('^#%s*(.-)%s*#@') or line:match('^#%s*(.-)%s*$')
                local cmd = line:match('#!%s*([^#@]+)')
                local checked_expr = line:match('#@checked=([^#]+)')
                local available_expr = line:match('#@available=([^#]+)')
                local item = {
                    title = title or 'Untitled',
                    cmd = cmd and cmd:match('^%s*(.-)%s*$'),
                    _check_fn = checked_expr and compile_expr(checked_expr),
                    _avail_fn = available_expr and compile_expr(available_expr),
                    submenu = {}
                }
                stack[#stack].node[#stack[#stack].node + 1] = item
                stack[#stack + 1] = { indent = indent, node = item.submenu }
            end
        end
    end
    return root
end

local function update_menu_data(items)
    local out = {}
    for i = 1, #items do
        local it = items[i]
        if it.type == 'separator' then
            out[#out + 1] = { type = 'separator' }
        else
            local ni = { title = it.title, cmd = it.cmd }
            if #it.submenu > 0 then
                ni.type = 'submenu'
                ni.submenu = update_menu_data(it.submenu)
            end
            local s = {}
            if it._check_fn then
                local ok, res = pcall(it._check_fn)
                if ok and res then s[#s + 1] = 'checked' end
            end
            if it._avail_fn then
                local ok, res = pcall(it._avail_fn)
                if ok and not res then s[#s + 1] = 'disabled' end
            end
            if #s > 0 then ni.state = s end
            out[#out + 1] = ni
        end
    end
    return out
end

local function init()
    is_init = is_init + 1
    if is_init <= 0 then return end
    state_tree = parse_menu()
    local data = update_menu_data(state_tree)
    mp.set_property_native('menu-data', data)
    mp.add_key_binding('MBTN_RIGHT', '__ctxmenu__', function()
        mp.set_property_native('menu-data', update_menu_data(state_tree))
        mp.command('context-menu')
    end)
    mp.unobserve_property(init)
end
mp.observe_property('menu-data', 'native', init)
