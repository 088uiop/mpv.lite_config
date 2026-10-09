local mp = require 'mp'
local utils = require 'mp.utils'

local vs = {
    state = {},
    preset = true,
    modes = {
        svp = {
            label = 'SVP',
            path = '~~/vs/svp.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                fnum = '60000',
                fden = '1001',
                abs = 'True',
                fmax = '60',
                nvof = 'False',
                gpu = '0'
            }
        },
        rife = {
            label = 'RIFE',
            path = '~~/vs/rife.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                be = '"ort_dml"',
                model = '46',
                fnum = '2',
                fden = '1',
                abs = 'False',
                fmax = '30',
                sc = 'True',
                gpu = '0',
                precision = '16',
            },
            static = { ['"trt"'] = false, ['"trt_rtx"'] = false }
        },
        drba = {
            label = 'DRBA',
            path = '~~/vs/drba.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                be = '"ort_dml"',
                model = '2',
                fnum = '2',
                fden = '1',
                abs = 'False',
                fmax = '30',
                sc = 'False',
                gpu = '0',
                precision = '16',
            },
            static = { ['"trt"'] = false }
        },
        realesrgan = {
            label = 'RealESRGAN',
            path = '~~/vs/realesrgan.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                be = '"ort_dml"',
                model = '5008',
                wlim = '1920',
                hlim = '1080',
                wmax = '3840',
                hmax = '2160',
                gpu = '0',
                precision = '16',
            },
            static = { ['"trt"'] = false, ['"trt_rtx"'] = false }
        },
        uai = {
            label = 'UAI',
            path = '~~/vs/uai.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                be = '"ort_dml"',
                model = '"HFA2kCompact_x2"',
                wlim = '1920',
                hlim = '1080',
                wmax = '3840',
                hmax = '2160',
                gpu = '0',
                precision = '16',
            },
            static = { ['"trt"'] = false, ['"trt_rtx"'] = false }
        }
    }
}
local finset = {
    state = false,
    value = 'container_fps'
}
local main_menu = {
    type = 'vs_main',
    title = 'VS选项',
    callback = { mp.get_script_name(), 'update_vs_main_menu' },
    items = {
        { title = '当前滤镜链: nil', selectable = false, bold = true, italic = true },
        { title = '清空', value = 'clear' },
        { title = '添加 SVP', value = 'add svp' },
        { title = '添加 RIFE', value = 'add rife' },
        { title = '添加 DRBA', value = 'add drba' },
        { title = '添加 RealESRGAN', value = 'add realesrgan' },
        { title = '添加 UAI', value = 'add uai' },
        { title = '非实时处理当前视频', value = 'process' },
        { title = '输入帧率修正', value = 'show finset' },
        { title = '配置菜单', value = 'show settings', actions = { { name = 'toggle_preset', icon = 'lock_open', label = '禁用' } } }
    }
}
local settings_menu = {
    type = 'vs_settings',
    title = 'VS配置',
    callback = { mp.get_script_name(), 'update_vs_settings_menu' },
    items = {
        {
            title = 'SVP 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'svp: wpre 1280; hpre 720 over' },
                        { title = '1080p', value = 'svp: wpre 1920; hpre 1080 over' },
                        { title = '1440p', value = 'svp: wpre 2560; hpre 1440 over' },
                        { title = '2160p', value = 'svp: wpre 3840; hpre 2160 over' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'svp: fnum 2; fden 1; abs False over' },
                        { title = '4x',     value = 'svp: fnum 4; fden 1; abs False over' },
                        { title = '8x',     value = 'svp: fnum 8; fden 1; abs False over' },
                        { title = '60fps',  value = 'svp: fnum 60000; fden 1001; abs True over' },
                        { title = '120fps', value = 'svp: fnum 120000; fden 1001; abs True over' },
                        { title = '240fps', value = 'svp: fnum 240000; fden 1001; abs True over' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '30fps',  value = 'svp: fmax 30 over' },
                        { title = '60fps',  value = 'svp: fmax 60 over' },
                        { title = '120fps', value = 'svp: fmax 120 over' }
                    }
                },
                {
                    title = 'NVOF',
                    items = {
                        { title = '关', value = 'svp: nvof False over' },
                        { title = '开', value = 'svp: nvof True over' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'svp: gpu 0 over' },
                        { title = 'GPU1', value = 'svp: gpu 1 over' }
                    }
                }
            }
        },
        {
            title = 'RIFE 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'rife: wpre 1280; hpre 720 over' },
                        { title = '1080p', value = 'rife: wpre 1920; hpre 1080 over' },
                        { title = '1440p', value = 'rife: wpre 2560; hpre 1440 over' },
                        { title = '2160p', value = 'rife: wpre 3840; hpre 2160 over' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'rife: be "ort_dml" over' },
                        { title = 'TRT', value = 'rife: be "trt" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'rife: be "trt_rtx" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'MIGX', value = 'rife: be "migx" over' }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'v4.6',        value = 'rife: model 46 over' },
                        { title = 'v4.25 lite',  value = 'rife: model 4251 over' },
                        { title = 'v4.26',       value = 'rife: model 426 over' },
                        { title = 'v4.26 heavy', value = 'rife: model 4262 over' }
                    }
                },
                {
                    title = '模型精度',
                    items = {
                        { title = 'fp16', value = 'rife: precision 16 over' },
                        { title = 'fp32', value = 'rife: precision 32 over' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'rife: fnum 2; fden 1; abs False over' },
                        { title = '3x',     value = 'rife: fnum 3; fden 1; abs False over' },
                        { title = '4x',     value = 'rife: fnum 4; fden 1; abs False over' },
                        { title = '60fps',  value = 'rife: fnum 60000; fden 1001; abs True over' },
                        { title = '90fps',  value = 'rife: fnum 90000; fden 1001; abs True over' },
                        { title = '120fps', value = 'rife: fnum 120000; fden 1001; abs True over' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '30fps',  value = 'rife: fmax 30 over' },
                        { title = '60fps',  value = 'rife: fmax 60 over' },
                        { title = '120fps', value = 'rife: fmax 120 over' }
                    }
                },
                {
                    title = '场景切换检测',
                    items = {
                        { title = '关', value = 'rife: sc False over' },
                        { title = '开', value = 'rife: sc True over' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'rife: gpu 0 over' },
                        { title = 'GPU1', value = 'rife: gpu 1 over' }
                    }
                }
            }
        },
        {
            title = 'DRBA 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'drba: wpre 1280; hpre 720 over' },
                        { title = '1080p', value = 'drba: wpre 1920; hpre 1080 over' },
                        { title = '1440p', value = 'drba: wpre 2560; hpre 1440 over' },
                        { title = '2160p', value = 'drba: wpre 3840; hpre 2160 over' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'drba: be "ort_dml" over' },
                        { title = 'TRT', value = 'drba: be "trt" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'drba: be "trt_rtx" over', hint = '此处仅静态引擎可用' },
                        { title = 'MIGX', value = 'drba: be "migx" over' }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'v1',      value = 'drba: model 1 over' },
                        { title = 'v2 lite', value = 'drba: model 2 over' }
                    }
                },
                {
                    title = '模型精度',
                    items = {
                        { title = 'fp16', value = 'drba: precision 16 over' },
                        { title = 'fp32', value = 'drba: precision 32 over' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'drba: fnum 2; fden 1; abs False over' },
                        { title = '3x',     value = 'drba: fnum 3; fden 1; abs False over' },
                        { title = '4x',     value = 'drba: fnum 4; fden 1; abs False over' },
                        { title = '60fps',  value = 'drba: fnum 60000; fden 1001; abs True over' },
                        { title = '90fps',  value = 'drba: fnum 90000; fden 1001; abs True over' },
                        { title = '120fps', value = 'drba: fnum 120000; fden 1001; abs True over' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '30fps',  value = 'drba: fmax 30 over' },
                        { title = '60fps',  value = 'drba: fmax 60 over' },
                        { title = '120fps', value = 'drba: fmax 120 over' }
                    }
                },
                {
                    title = '场景切换检测',
                    items = {
                        { title = '关', value = 'drba: sc False over' },
                        { title = '开', value = 'drba: sc True over' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'drba: gpu 0 over' },
                        { title = 'GPU1', value = 'drba: gpu 1 over' }
                    }
                }
            }
        },
        {
            title = 'RealESRGAN 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'realesrgan: wpre 1280; hpre 720 over' },
                        { title = '1080p', value = 'realesrgan: wpre 1920; hpre 1080 over' },
                        { title = '1440p', value = 'realesrgan: wpre 2560; hpre 1440 over' },
                        { title = '2160p', value = 'realesrgan: wpre 3840; hpre 2160 over' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'realesrgan: be "ort_dml" over' },
                        { title = 'TRT', value = 'realesrgan: be "trt" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'realesrgan: be "trt_rtx" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'MIGX', value = 'realesrgan: be "migx" over' }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'animevideov3',         value = 'realesrgan: model 2 over' },
                        { title = 'janaiV3_HD_L1',        value = 'realesrgan: model 5008 over' },
                        { title = 'janaiV3_HD_L2',        value = 'realesrgan: model 5009 over' },
                        { title = 'janaiV3_HD_L3',        value = 'realesrgan: model 5010 over' },
                        { title = 'Ani4Kv2_Compact',      value = 'realesrgan: model 7000 over' },
                        { title = 'Ani4Kv2_UltraCompact', value = 'realesrgan: model 7001 over' }
                    }
                },
                {
                    title = '模型精度',
                    items = {
                        { title = 'fp16', value = 'realesrgan: precision 16 over' },
                        { title = 'fp32', value = 'realesrgan: precision 32 over' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '720p',  value = 'realesrgan: wlim 1280; hlim 720 over' },
                        { title = '1080p', value = 'realesrgan: wlim 1920; hlim 1080 over' },
                        { title = '2160p', value = 'realesrgan: wlim 3840; hlim 2160 over' }
                    }
                },
                {
                    title = '限制输出',
                    items = {
                        { title = '1440p', value = 'realesrgan: wmax 2560; hmax 1440 over' },
                        { title = '2160p', value = 'realesrgan: wmax 3840; hmax 2160 over' },
                        { title = '4320p', value = 'realesrgan: wmax 7680; hmax 4320 over' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'realesrgan: gpu 0 over' },
                        { title = 'GPU1', value = 'realesrgan: gpu 1 over' }
                    }
                }
            }
        },
        {
            title = 'UAI 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'uai: wpre 1280; hpre 720 over' },
                        { title = '1080p', value = 'uai: wpre 1920; hpre 1080 over' },
                        { title = '1440p', value = 'uai: wpre 2560; hpre 1440 over' },
                        { title = '2160p', value = 'uai: wpre 3840; hpre 2160 over' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'uai: be "ort_dml" over' },
                        { title = 'TRT', value = 'uai: be "trt" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'uai: be "trt_rtx" over', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'MIGX', value = 'uai: be "migx" over' }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'HFA2kCompact_x2',        value = 'uai: model "HFA2kCompact_x2" over' },
                        { title = 'HFA2kSpan_x2',           value = 'uai: model "HFA2kSpan_x2" over' },
                        { title = 'ClearRealityV1_x4',      value = 'uai: model "ClearRealityV1_x4" over' },
                        { title = 'ClearRealityV1_Soft_x4', value = 'uai: model "ClearRealityV1_Soft_x4" over' }
                    }
                },
                {
                    title = '模型精度',
                    items = {
                        { title = 'fp16', value = 'uai: precision 16 over' },
                        { title = 'fp32', value = 'uai: precision 32 over' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '720p',  value = 'uai: wlim 1280; hlim 720 over' },
                        { title = '1080p', value = 'uai: wlim 1920; hlim 1080 over' },
                        { title = '2160p', value = 'uai: wlim 3840; hlim 2160 over' }
                    }
                },
                {
                    title = '限制输出',
                    items = {
                        { title = '1440p', value = 'uai: wmax 2560; hmax 1440 over' },
                        { title = '2160p', value = 'uai: wmax 3840; hmax 2160 over' },
                        { title = '4320p', value = 'uai: wmax 7680; hmax 4320 over' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'uai: gpu 0 over' },
                        { title = 'GPU1', value = 'uai: gpu 1 over' }
                    }
                }
            }
        }
    }
}
local finset_menu = {
    type = 'vs_finset',
    title = '补帧输入帧率',
    search_debounce = 'submit',
    search_style = 'palette',
    on_search = 'callback',
    callback = { mp.get_script_name(), 'update_vs_finset_menu' },
    items = {
        { title = '当前输入帧率: ', hint = '无数据' },
        { title = '重置为视频默认' }
    }
}

local function parse_command(str)
    if not str then return {} end
    local mode, cmds = str:match("^%s*([^:]-)%s*:%s*(.*)$")
    local commands = {}
    for cmd in cmds:gmatch("[^;]+") do
        local args = {}
        for arg in cmd:gmatch("%S+") do
            args[#args + 1] = arg
        end
        commands[#commands + 1] = args
    end
    return { mode = mode, commands = commands }
end

local function update(no_osd, fin)
    mp.set_property_native('user-data/vs', vs)
    local tags = {}
    for _, mode in ipairs(vs.state) do tags[#tags + 1] = vs.modes[mode].label end
    local str = table.concat(tags, ' >> ')
    if str == '' then str = 'nil' end
    if not no_osd then mp.osd_message('VS: ' .. str) end
    main_menu.items[1].title = '当前滤镜链: ' .. str
    local preset_menu = main_menu.items[#main_menu.items]
    preset_menu.muted = not vs.preset
    preset_menu.actions[1].icon = vs.preset and 'lock_open' or 'lock'
    preset_menu.actions[1].label = vs.preset and '禁用' or '启用'
    local mis = { 'svp', 'rife', 'drba', 'realesrgan', 'uai' }
    local bis = { '"dml"', '"trt"', '"trt_rtx"' }
    for i, setting in ipairs(settings_menu.items) do
        for _, option in ipairs(setting.items) do
            for j, item in ipairs(option.items) do
                local active = true
                local cmd = parse_command(item.value)
                for _, args in ipairs(cmd.commands) do
                    if vs.modes[cmd.mode].settings[args[1]] ~= args[2] then
                        active = false
                        break
                    end
                end
                item.active = active
                if item.actions then
                    item.actions[1].icon = vs.modes[mis[i]].static[bis[j]] and 'toggle_on' or 'toggle_off'
                end
            end
        end
    end
    for _, mode in pairs(vs.modes) do
        if not vs.preset and not fin then break end
        local script_path = mp.command_native({ 'expand-path', mode.path })
        local script = io.open(script_path, 'r')
        if script then
            local new_script_parts = {}
            for line in script:lines() do
                if vs.preset then
                    if line:find('static%s*=') then
                        line = 'static = ' .. (mode.static[mode.settings.be] and 'True' or 'False')
                    else
                        for k, v in pairs(mode.settings) do
                            if line:find(k .. '%s*=') then
                                line = k .. ' = ' .. v
                                break
                            end
                        end
                    end
                end
                if fin and line:find('fin%s*=') then
                    line = 'fin = ' .. fin
                end
                new_script_parts[#new_script_parts + 1] = line
            end
            script:close()
            local new_script = io.open(script_path, 'w')
            if new_script then
                new_script:write(table.concat(new_script_parts, '\n'))
                new_script:close()
            end
        end
    end
    for i, mode in ipairs(vs.state) do
        mp.commandv('vf', 'add', '@VS' .. i .. ':vapoursynth:file=' .. vs.modes[mode].path)
    end
end

local function clear_mode()
    for i = 1, #vs.state do mp.commandv('vf', 'remove', '@VS' .. i) end
    vs.state = {}
    update()
end

local function add_mode(mode)
    vs.state[#vs.state + 1] = mode
    update()
end

local function set_mode(mode, key, value, over)
    for i = 1, #vs.state do mp.commandv('vf', 'remove', '@VS' .. i) end
    vs.modes[mode].settings[key] = value
    if over == 'over' then update(true) end
end

local function show_menu(menu)
    if menu == 'settings' and not vs.preset then return end
    local menus = { main = main_menu, settings = settings_menu, finset = finset_menu }
    mp.commandv('script-message-to', 'uosc', 'open-menu', utils.format_json(menus[menu]))
end

local function convert_vpy(file_path)
    local abs_path = mp.command_native({ 'expand-path', file_path })
    local file = io.open(abs_path, 'r')
    if not file then return '' end
    local content = file:read('*all')
    file:close()
    local vars = {}
    local output_lines = {}
    for line in content:gmatch('[^\r\n]+') do
        if not line:find('clip%s*=') and not line:find('^%s*#') then
            local name, value = line:match('([%w_]+)%s*=%s*([^%s\n#]+)')
            if name then vars[name] = value end
        end
        local method, args_raw = line:match('clip%s*=%s*k7sfunc%.([%w_]+)%((.*)%)')
        if method and args_raw then
            local processed_args = {}
            for arg in args_raw:gmatch('([^,]+)') do
                arg = arg:gsub('^%s*(.-)%s*$', '%1')
                local arg_map = { clip = 'clip', fin = 'clip.fps', nvof = 'False' }
                processed_args[#processed_args + 1] = arg_map[arg] or vars[arg] or arg
            end
            local args = table.concat(processed_args, ', ')
            output_lines[#output_lines + 1] = string.format('clip = k7sfunc.%s(%s)', method, args)
        end
    end
    return table.concat(output_lines, '\n')
end

local function create_vpy(video_path)
    local targets = {}
    for _, mode in ipairs(vs.state) do targets[#targets + 1] = vs.modes[mode].path end
    local temp_path = os.getenv('TEMP')
    local script_parts = {
        'import k7sfunc',
        'import vapoursynth',
        string.format('clip = vapoursynth.core.lsmas.LWLibavSource(source=%q, cachedir=%q)', video_path, temp_path),
    }
    for _, path in ipairs(targets) do script_parts[#script_parts + 1] = convert_vpy(path) end
    script_parts[#script_parts + 1] = 'clip.set_output()'
    local script = table.concat(script_parts, '\n')
    local temp_file = temp_path .. '/vspipe_master.vpy'
    local file = io.open(temp_file, 'w')
    if file then
        file:write(script)
        file:close()
        return temp_file
    end
end

local function process_video()
    if not next(vs.state) then
        mp.msg.warn('当前未添加任何VS滤镜')
        return
    end
    local video_path = mp.get_property('path')
    if not video_path then
        mp.msg.warn('当前未加载视频')
        return
    end
    local vpy_path = create_vpy(video_path)
    if not vpy_path then
        mp.msg.error('脚本生成失败')
        return
    end
    local dir, name = video_path:match('(.*)[/\\](.*)$')
    if not dir then dir = '.' end
    local stem = name:match('(.+)%..+$') or name
    local output_path = dir .. '/' .. stem .. '_processed.mkv'
    local mpv_path = mp.command_native({ 'expand-path', '~~/../' })
    local vp = mp.get_property_native('video-params', {})
    local x265_params = string.format(
        '-x265-params "colorprim=%s:colormatrix=%s:transfer=%s:range=%s"',
        vp.primaries == 'bt.2020' and 'bt2020' or 'bt709',
        vp.colormatrix == 'bt.2020-ncl' and 'bt2020nc' or 'bt709',
        vp.gamma == 'pq' and 'smpte2084' or vp.gamma == 'hlg' and 'arib-std-b67' or 'bt709',
        vp.colorlevels or 'limited'
    )
    if vp['max-cll'] then
        x265_params = x265_params:gsub('"$', string.format(
            ':max-cll=%d,%d:hdr10=1"',
            vp['max-cll'],
            vp['max-fall']
        ))
    end
    local function esc(p) return string.gsub(p, '[%%^&]', { ['%%'] = '%%%%', ['^'] = '^^', ['&'] = '^&' }) end
    local cmd = string.format(
        'cmd /c start /b "process video" cmd /c "cd /d %q & vspipe -c y4m %q - -p | ffmpeg -y -hide_banner -loglevel error -i - -i %q -map 0:v -map 1:a? -map 1:s? -map 1:t? -c:v libx265 -crf 18 -pix_fmt p010 %s -c:a copy -c:s copy -c:t copy %q & pause"',
        esc(mpv_path), esc(vpy_path), esc(video_path), x265_params, esc(output_path)
    )
    os.execute(cmd)
end

local function toggle_preset()
    vs.preset = not vs.preset
    update(true)
end

local function toggle_static(mode, be)
    vs.modes[mode].static[be] = not vs.modes[mode].static[be]
    update(true)
end

local function init(_, loaded)
    if not loaded then return end
    local vspipe = io.open(mp.command_native({ 'expand-path', '~~/../VSPipe.exe' }))
    local vs_checked = vspipe ~= nil
    if vspipe then vspipe:close() end
    mp.set_property_bool('user-data/vs_checked', vs_checked)
    if not vs_checked then
        mp.msg.warn('未检测到VapourSynth，VS相关功能已禁用')
        mp.unobserve_property(init)
        return
    end
    vs = mp.get_property_native('user-data/vs', vs)
    update(true, 'container_fps')
    mp.register_event('file-loaded', function()
        finset_menu.items[1].hint = finset.state and finset.value or mp.get_property('container-fps', '无数据')
    end)
    mp.register_event('end-file', function()
        finset_menu.items[1].hint = '无数据'
    end)
    mp.register_script_message('update_vs_main_menu', function(json)
        local event = utils.parse_json(json)
        if event.action == 'toggle_preset' then
            toggle_preset()
        elseif event.value then
            local functions = { clear = clear_mode, add = add_mode, show = show_menu, process = process_video }
            local arg1, arg2 = event.value:match("^(%S+)%s*(.*)$")
            functions[arg1](arg2)
        end
        mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(main_menu))
    end)
    mp.register_script_message('update_vs_settings_menu', function(json)
        local event = utils.parse_json(json)
        local cmd = parse_command(event.value)
        if event.action == 'toggle_static' then
            toggle_static(cmd.mode, cmd.commands[1][2])
        elseif event.value then
            for _, args in ipairs(cmd.commands) do set_mode(cmd.mode, args[1], args[2], args[3]) end
        end
        mp.commandv('script-message-to', 'uosc', 'update-menu', utils.format_json(settings_menu))
    end)
    mp.register_script_message('update_vs_finset_menu', function(json)
        local event = utils.parse_json(json)
        local def = event.type == 'search'
        local redef = event.type == 'activate' and event.index == 2
        if def or redef then
            for i = 1, #vs.state do mp.commandv('vf', 'remove', '@VS' .. i) end
            finset.state = def
            finset.value = def and event.query or 'container_fps'
            update(true, finset.value)
            finset_menu.items[1].hint = def and finset.value or mp.get_property('container-fps', '无数据')
            mp.commandv('script-message-to', 'uosc', def and 'open-menu' or 'update-menu', utils.format_json(finset_menu))
        end
    end)
    mp.register_script_message('clear_vs_mode', clear_mode)
    mp.register_script_message('add_vs_mode', add_mode)
    mp.register_script_message('set_vs_mode', set_mode)
    mp.register_script_message('show_vs_menu', show_menu)
    mp.register_script_message('vs_process_video', process_video)
    mp.register_script_message('toggle_vs_preset', toggle_preset)
    mp.register_script_message('toggle_vs_static', toggle_static)
    mp.unobserve_property(init)
end
mp.observe_property('user-data/__state_loaded__', 'bool', init)
