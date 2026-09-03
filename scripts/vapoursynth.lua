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
                static = 'False'
            }
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
                static = 'False'
            }
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
                static = 'False'
            }
        },
        uai = {
            label = 'UAI',
            path = '~~/vs/uai.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                be = '"ort_dml"',
                model = '"HFA2kCompact_x2.onnx"',
                wlim = '1920',
                hlim = '1080',
                wmax = '3840',
                hmax = '2160',
                gpu = '0',
                static = 'False'
            }
        }
    }
}
local main_menu = {
    type = 'vs_main',
    title = 'VS选项',
    callback = { mp.get_script_name(), "update_vs_main_menu" },
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
    callback = { mp.get_script_name(), "update_vs_settings_menu" },
    items = {
        {
            title = 'SVP 配置',
            items = {
                {
                    title = '预降低分辨率',
                    items = {
                        { title = '720p',  value = 'set svp wpre 1280; set svp hpre 720' },
                        { title = '1080p', value = 'set svp wpre 1920; set svp hpre 1080' },
                        { title = '1440p', value = 'set svp wpre 2560; set svp hpre 1440' },
                        { title = '2160p', value = 'set svp wpre 3840; set svp hpre 2160' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'set svp fnum 2; set svp fden 1; set svp abs False' },
                        { title = '4x',     value = 'set svp fnum 4; set svp fden 1; set svp abs False' },
                        { title = '8x',     value = 'set svp fnum 8; set svp fden 1; set svp abs False' },
                        { title = '60fps',  value = 'set svp fnum 60000; set svp fden 1001; set svp abs True' },
                        { title = '120fps', value = 'set svp fnum 120000; set svp fden 1001; set svp abs True' },
                        { title = '240fps', value = 'set svp fnum 240000; set svp fden 1001; set svp abs True' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '60fps',  value = 'set svp fmax 60' },
                        { title = '120fps', value = 'set svp fmax 120' },
                        { title = '240fps', value = 'set svp fmax 240' }
                    }
                },
                {
                    title = 'NVOF',
                    items = {
                        { title = '关', value = 'set svp nvof False' },
                        { title = '开', value = 'set svp nvof True' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'set svp gpu 0' },
                        { title = 'GPU1', value = 'set svp gpu 1' }
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
                        { title = '720p',  value = 'set rife wpre 1280; set rife hpre 720' },
                        { title = '1080p', value = 'set rife wpre 1920; set rife hpre 1080' },
                        { title = '1440p', value = 'set rife wpre 2560; set rife hpre 1440' },
                        { title = '2160p', value = 'set rife wpre 3840; set rife hpre 2160' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'set rife be "ort_dml"' },
                        { title = 'TRT', value = 'set rife be "trt"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'set rife be "trt_rtx"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'v4.6',        value = 'set rife model 46' },
                        { title = 'v4.25 lite',  value = 'set rife model 4251' },
                        { title = 'v4.26',       value = 'set rife model 426' },
                        { title = 'v4.26 heavy', value = 'set rife model 4262' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'set rife fnum 2; set rife fden 1; set rife abs False' },
                        { title = '3x',     value = 'set rife fnum 3; set rife fden 1; set rife abs False' },
                        { title = '4x',     value = 'set rife fnum 4; set rife fden 1; set rife abs False' },
                        { title = '60fps',  value = 'set rife fnum 60000; set rife fden 1001; set rife abs True' },
                        { title = '90fps',  value = 'set rife fnum 90000; set rife fden 1001; set rife abs True' },
                        { title = '120fps', value = 'set rife fnum 120000; set rife fden 1001; set rife abs True' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '30fps', value = 'set rife fmax 30' },
                        { title = '60fps', value = 'set rife fmax 60' },
                        { title = '90fps', value = 'set rife fmax 90' }
                    }
                },
                {
                    title = '场景切换检测',
                    items = {
                        { title = '关', value = 'set rife sc False' },
                        { title = '开', value = 'set rife sc True' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'set rife gpu 0' },
                        { title = 'GPU1', value = 'set rife gpu 1' }
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
                        { title = '720p',  value = 'set drba wpre 1280; set drba hpre 720' },
                        { title = '1080p', value = 'set drba wpre 1920; set drba hpre 1080' },
                        { title = '1440p', value = 'set drba wpre 2560; set drba hpre 1440' },
                        { title = '2160p', value = 'set drba wpre 3840; set drba hpre 2160' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'set drba be "ort_dml"' },
                        { title = 'TRT', value = 'set drba be "trt"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'set drba be "trt_rtx"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'v1',      value = 'set drba model 1' },
                        { title = 'v2 lite', value = 'set drba model 2' }
                    }
                },
                {
                    title = '输出',
                    items = {
                        { title = '2x',     value = 'set drba fnum 2; set drba fden 1; set drba abs False' },
                        { title = '3x',     value = 'set drba fnum 3; set drba fden 1; set drba abs False' },
                        { title = '4x',     value = 'set drba fnum 4; set drba fden 1; set drba abs False' },
                        { title = '60fps',  value = 'set drba fnum 60000; set drba fden 1001; set drba abs True' },
                        { title = '90fps',  value = 'set drba fnum 90000; set drba fden 1001; set drba abs True' },
                        { title = '120fps', value = 'set drba fnum 120000; set drba fden 1001; set drba abs True' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '30fps', value = 'set drba fmax 30' },
                        { title = '60fps', value = 'set drba fmax 60' },
                        { title = '90fps', value = 'set drba fmax 90' }
                    }
                },
                {
                    title = '场景切换检测',
                    items = {
                        { title = '关', value = 'set drba sc False' },
                        { title = '开', value = 'set drba sc True' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'set drba gpu 0' },
                        { title = 'GPU1', value = 'set drba gpu 1' }
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
                        { title = '720p',  value = 'set realesrgan wpre 1280; set realesrgan hpre 720' },
                        { title = '1080p', value = 'set realesrgan wpre 1920; set realesrgan hpre 1080' },
                        { title = '1440p', value = 'set realesrgan wpre 2560; set realesrgan hpre 1440' },
                        { title = '2160p', value = 'set realesrgan wpre 3840; set realesrgan hpre 2160' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'set realesrgan be "ort_dml"' },
                        { title = 'TRT', value = 'set realesrgan be "trt"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'set realesrgan be "trt_rtx"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'animevideov3',         value = 'set realesrgan model 2' },
                        { title = 'janaiV3_HD_L1',        value = 'set realesrgan model 5008' },
                        { title = 'janaiV3_HD_L2',        value = 'set realesrgan model 5009' },
                        { title = 'janaiV3_HD_L3',        value = 'set realesrgan model 5010' },
                        { title = 'Ani4Kv2_Compact',      value = 'set realesrgan model 7000' },
                        { title = 'Ani4Kv2_UltraCompact', value = 'set realesrgan model 7001' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '720p',  value = 'set realesrgan wlim 1280; set realesrgan hlim 720' },
                        { title = '1080p', value = 'set realesrgan wlim 1920; set realesrgan hlim 1080' },
                        { title = '2160p', value = 'set realesrgan wlim 3840; set realesrgan hlim 2160' }
                    }
                },
                {
                    title = '限制输出',
                    items = {
                        { title = '1440p', value = 'set realesrgan wmax 2560; set realesrgan hmax 1440' },
                        { title = '2160p', value = 'set realesrgan wmax 3840; set realesrgan hmax 2160' },
                        { title = '4320p', value = 'set realesrgan wmax 7680; set realesrgan hmax 4320' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'set realesrgan gpu 0' },
                        { title = 'GPU1', value = 'set realesrgan gpu 1' }
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
                        { title = '720p',  value = 'set uai wpre 1280; set uai hpre 720' },
                        { title = '1080p', value = 'set uai wpre 1920; set uai hpre 1080' },
                        { title = '1440p', value = 'set uai wpre 2560; set uai hpre 1440' },
                        { title = '2160p', value = 'set uai wpre 3840; set uai hpre 2160' }
                    }
                },
                {
                    title = '后端',
                    items = {
                        { title = 'DML', value = 'set uai be "ort_dml"' },
                        { title = 'TRT', value = 'set uai be "trt"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } },
                        { title = 'TRT_RTX', value = 'set uai be "trt_rtx"', actions = { { name = 'toggle_static', icon = 'toggle_off', label = '静态引擎开关' } } }
                    }
                },
                {
                    title = '模型',
                    items = {
                        { title = 'HFA2kCompact_x2',        value = 'set uai model "HFA2kCompact_x2.onnx"' },
                        { title = 'HFA2kReal_CUGAN_x2',     value = 'set uai model "HFA2kReal_CUGAN_x2.onnx"' },
                        { title = 'HFA2kSpan_x2',           value = 'set uai model "HFA2kSpan_x2.onnx"' },
                        { title = 'ClearRealityV1_x4',      value = 'set uai model "ClearRealityV1_x4.onnx"' },
                        { title = 'ClearRealityV1_Soft_x4', value = 'set uai model "ClearRealityV1_Soft_x4.onnx"' }
                    }
                },
                {
                    title = '限制输入',
                    items = {
                        { title = '720p',  value = 'set uai wlim 1280; set uai hlim 720' },
                        { title = '1080p', value = 'set uai wlim 1920; set uai hlim 1080' },
                        { title = '2160p', value = 'set uai wlim 3840; set uai hlim 2160' }
                    }
                },
                {
                    title = '限制输出',
                    items = {
                        { title = '1440p', value = 'set uai wmax 2560; set uai hmax 1440' },
                        { title = '2160p', value = 'set uai wmax 3840; set uai hmax 2160' },
                        { title = '4320p', value = 'set uai wmax 7680; set uai hmax 4320' }
                    }
                },
                {
                    title = '使用的 GPU',
                    items = {
                        { title = 'GPU0', value = 'set uai gpu 0' },
                        { title = 'GPU1', value = 'set uai gpu 1' }
                    }
                }
            }
        }
    }
}
local finset_menu = {
    type = "vs_finset",
    title = "补帧输入帧率",
    search_debounce = "submit",
    search_style = "palette",
    on_search = "callback",
    callback = { mp.get_script_name(), "update_vs_finset_menu" },
    items = {
        { title = "当前输入帧率: ", hint = "无数据" },
        { title = "重置为视频默认" }
    }
}
local findef = false

local function parse_command(str)
    local args = {}
    for command in str:gmatch("([^;]+)%s*") do
        local arg = {}
        for part in command:gmatch("%S+") do
            table.insert(arg, part)
        end
        table.insert(args, arg)
    end
    return args
end

local function clear()
    mp.set_property_native("user-data/vs", vs)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label:find("VS") then
            mp.commandv("vf", "remove", "@" .. filter.label)
        end
    end
end

local function update(no_osd, fin)
    mp.set_property_native("user-data/vs", vs)
    local tags = {}
    for _, mode in ipairs(vs.state) do table.insert(tags, vs.modes[mode].label) end
    local str = table.concat(tags, " >> ")
    if str == "" then str = "nil" end
    if not no_osd then mp.osd_message("VS: " .. str) end
    for _, item in ipairs(main_menu.items) do
        if item.title:find("当前滤镜链: ") then
            item.title = "当前滤镜链: " .. str
        end
    end
    for _, item in ipairs(main_menu.items) do
        if item.title == "配置菜单" then
            item.muted = not vs.preset
            item.actions[1].icon = vs.preset and "lock_open" or "lock"
            item.actions[1].label = vs.preset and "禁用" or "启用"
        end
    end
    for _, mode in ipairs(settings_menu.items) do
        for _, option in ipairs(mode.items) do
            for _, item in ipairs(option.items) do
                local acitve = true
                local args = parse_command(item.value)
                for _, arg in ipairs(args) do
                    if arg[4]:find("trt") then
                        local static = vs.modes[arg[2]].settings.static == "True"
                        item.actions[1].icon = static and "toggle_on" or "toggle_off"
                    end
                    if vs.modes[arg[2]].settings[arg[3]] ~= arg[4] then
                        acitve = false
                        break
                    end
                end
                item.active = acitve
            end
        end
    end
    for _, mode in pairs(vs.modes) do
        if not vs.preset and not fin then break end
        local script_path = mp.command_native({ "expand-path", mode.path })
        local script = io.open(script_path, 'r')
        if script then
            local new_script_parts = {}
            for line in script:lines() do
                if vs.preset then
                    for k, v in pairs(mode.settings) do
                        if line:find(k .. "%s*=") then
                            line = k .. " = " .. v
                            break
                        end
                    end
                end
                if fin and line:find("fin%s*=") then
                    line = "fin = " .. fin
                end
                table.insert(new_script_parts, line)
            end
            script:close()
            local new_script = io.open(script_path, 'w')
            if new_script then
                new_script:write(table.concat(new_script_parts, "\n"))
                new_script:close()
            end
        end
    end
    for i, mode in ipairs(vs.state) do
        mp.commandv("vf", "add", "@VS" .. i .. ":vapoursynth:file=" .. vs.modes[mode].path)
    end
end

local function clear_mode()
    vs.state = {}
    clear()
    update()
end

local function add_mode(mode)
    table.insert(vs.state, mode)
    update()
end

local function set_mode(mode, key, value)
    vs.modes[mode].settings[key] = value
    clear()
    update(true)
end

local function show_menu(menu)
    local menus = {
        settings = settings_menu,
        finset = finset_menu
    }
    if menu == "settings" and not vs.preset then return end
    mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(menus[menu] or main_menu))
end

local function convert_vpy(file_path)
    local abs_path = mp.command_native({ "expand-path", file_path })
    local file = io.open(abs_path, "r")
    if not file then return "" end
    local content = file:read("*all")
    file:close()
    local vars = {}
    local output_lines = {}
    for line in content:gmatch("[^\r\n]+") do
        if not line:find("clip%s*=") and not line:find("^%s*#") then
            local name, value = line:match("([%w_]+)%s*=%s*([^%s\n#]+)")
            if name then vars[name] = value end
        end
        local method, args_raw = line:match("clip%s*=%s*k7sfunc%.([%w_]+)%((.*)%)")
        if method and args_raw then
            local processed_args = {}
            for arg in args_raw:gmatch("([^,]+)") do
                arg = arg:gsub("^%s*(.-)%s*$", "%1")
                if arg == "video_in" or arg == "clip" then
                    table.insert(processed_args, "clip")
                elseif arg == "container_fps" or arg == "fin" then
                    table.insert(processed_args, "clip.fps")
                else
                    table.insert(processed_args, vars[arg] or arg)
                end
            end
            table.insert(output_lines, string.format("clip = k7sfunc.%s(%s)", method, table.concat(processed_args, ", ")))
        end
    end
    return table.concat(output_lines, "\n")
end

local function create_vpy(video_path)
    local targets = {}
    for _, mode in ipairs(vs.state) do table.insert(targets, vs.modes[mode].path) end
    local script_parts = {
        "import k7sfunc",
        "import vapoursynth",
        string.format("clip = vapoursynth.core.lsmas.LWLibavSource(source=%q)", video_path),
    }
    for _, path in ipairs(targets) do table.insert(script_parts, convert_vpy(path)) end
    table.insert(script_parts, "clip.set_output()")
    local script = table.concat(script_parts, "\n")
    local temp_file = os.getenv("TEMP") .. "/vspipe_master.vpy"
    local file = io.open(temp_file, "w")
    if file then
        file:write(script)
        file:close()
        return temp_file
    end
end

local function encode_video()
    if not next(vs.state) then
        mp.msg.warn("当前未添加任何VS滤镜")
        return
    end
    local video_path = mp.get_property("path")
    if not video_path then
        mp.msg.warn("当前未加载视频")
        return
    end
    local vpy_path = create_vpy(video_path)
    if not vpy_path then
        mp.msg.error("脚本生成失败")
        return
    end
    local dir, name = video_path:match("(.*)[/\\](.*)$")
    if not dir then dir = "." end
    local stem = name:match("(.+)%..+$") or name
    local output_path = dir .. "/" .. stem .. "_processed.mkv"
    local mpv_path = mp.command_native({ "expand-path", "~~/../" })
    local function esc(p) return string.gsub(p, "[%%^&]", { ["%%"] = "%%%%", ["^"] = "^^", ["&"] = "^&" }) end
    local vp = mp.get_property_native("video-params")
    local x265_params = string.format(
        '-x265-params "colorprim=%s:colormatrix=%s:transfer=%s:range=%s"',
        vp.primaries == "bt.2020" and "bt2020" or "bt709",
        vp.colormatrix == "bt.2020-ncl" and "bt2020nc" or "bt709",
        vp.gamma == "pq" and "smpte2084" or vp.gamma == "hlg" and "arib-std-b67" or vp.gamma,
        vp.colorlevels
    )
    if vp["max-cll"] then
        x265_params = x265_params:gsub('" ', string.format(
            ':max-cll=%d,%d:hdr10=1" ',
            vp["max-cll"],
            vp["max-fall"]
        ))
    end
    local cmd = string.format(
        'cmd /c "cd /d %q & vspipe -c y4m %q - -p | ffmpeg -y -hide_banner -loglevel error -thread_queue_size 2048 -i - -i %q -map 0:v -map 1:a? -map 1:s? -map 1:t? -c:v libx265 -crf 18 -pix_fmt p010 %s -c:a copy -c:s copy -c:t copy %q & pause"',
        esc(mpv_path), esc(vpy_path), esc(video_path), x265_params, esc(output_path)
    )
    os.execute(cmd)
    os.remove(video_path .. ".lwi")
end

local functions = {
    clear = clear_mode,
    add = add_mode,
    set = set_mode,
    show = show_menu,
    process = encode_video
}

local function init(_, loaded)
    if not loaded then return end
    VS_Checked = io.open(mp.command_native({ "expand-path", "~~/../VSPipe.exe" })) and true or false
    mp.set_property_native("user-data/vs_checked", VS_Checked)
    if not VS_Checked then
        mp.msg.warn("未检测到VapourSynth，VS相关功能已禁用")
        mp.unobserve_property(init)
        return
    end
    local saved = mp.get_property_native("user-data/vs")
    if saved then vs = saved end
    update(true, "container_fps")
    mp.register_event("file-loaded", function()
        for _, item in ipairs(finset_menu.items) do
            if item.title == "当前输入帧率: " then
                item.hint = findef and item.hint or mp.get_property("container-fps")
            end
        end
    end)
    mp.register_script_message("update_vs_main_menu", function(json)
        local event = utils.parse_json(json)
        if event.action == "toggle_preset" then
            vs.preset = not vs.preset
            update(true)
        elseif event.value then
            local args = parse_command(event.value)
            for _, arg in ipairs(args) do
                functions[arg[1]](arg[2])
            end
        end
        mp.commandv("script-message-to", "uosc", "update-menu", utils.format_json(main_menu))
    end)
    mp.register_script_message("update_vs_settings_menu", function(json)
        local event = utils.parse_json(json)
        if event.value then
            local args = parse_command(event.value)
            if event.action == "toggle_static" then
                for _, arg in ipairs(args) do
                    local value = vs.modes[arg[2]].settings.static == "True" and "False" or "True"
                    set_mode(arg[2], "static", value)
                end
            else
                for _, arg in ipairs(args) do
                    functions[arg[1]](arg[2], arg[3], arg[4])
                end
            end
        end
        mp.commandv("script-message-to", "uosc", "update-menu", utils.format_json(settings_menu))
    end)
    mp.register_script_message("update_vs_finset_menu", function(json)
        local event = utils.parse_json(json)
        if event.type == "activate" and finset_menu.items[event.index].title == "重置为视频默认" then
            clear()
            findef = false
            update(true, "container_fps")
            for _, item in ipairs(finset_menu.items) do
                if item.title == "当前输入帧率: " then item.hint = mp.get_property("container-fps") or "无数据" end
            end
            mp.commandv("script-message-to", "uosc", "update-menu", utils.format_json(finset_menu))
        elseif event.type == "search" then
            clear()
            findef = true
            update(true, event.query)
            for _, item in ipairs(finset_menu.items) do
                if item.title == "当前输入帧率: " then item.hint = event.query end
            end
            mp.commandv("script-message-to", "uosc", "open-menu", utils.format_json(finset_menu))
        end
    end)
    mp.register_script_message("toggle_vs_preset", function()
        vs.preset = not vs.preset
        update(true)
    end)
    mp.register_script_message("clear_vs_mode", clear_mode)
    mp.register_script_message("add_vs_mode", add_mode)
    mp.register_script_message("set_vs_mode", set_mode)
    mp.register_script_message("show_vs_main_menu", show_menu)
    mp.register_script_message("vs_process_video", encode_video)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
