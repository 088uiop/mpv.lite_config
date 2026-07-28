local mp = require 'mp'

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
                trt = 'True',
                rtx = 'False',
                static = 'True',
                model = '46',
                fnum = '2',
                fden = '1',
                abs = 'False',
                fmax = '30',
                sc = 'True',
                gpu = '0'
            }
        },
        realesrgan = {
            label = 'RealESRGAN',
            path = '~~/vs/realesrgan.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                trt = 'True',
                rtx = 'False',
                static = 'True',
                model = '5008',
                wlim = '1920',
                hlim = '1080',
                wmax = '3840',
                hmax = '2160',
                gpu = '0'
            }
        },
        uai = {
            label = 'UAI',
            path = '~~/vs/uai.vpy',
            settings = {
                wpre = '1920',
                hpre = '1080',
                trt = 'True',
                rtx = 'False',
                static = 'True',
                model = '"HFA2kCompact_x2.onnx"',
                wlim = '1920',
                hlim = '1080',
                wmax = '3840',
                hmax = '2160',
                gpu = '0'
            }
        }
    }
}

local function clear()
    mp.set_property_native("user-data/vs", vs)
    local vf = mp.get_property_native("vf")
    for _, filter in ipairs(vf) do
        if filter.label:find("VS") then
            mp.commandv("vf", "remove", "@" .. filter.label)
        end
    end
end

local function update()
    mp.set_property_native("user-data/vs", vs)
    for _, mode in pairs(vs.modes) do
        if not vs.preset then break end
        local script_path = mp.command_native({ "expand-path", mode.path })
        local script = io.open(script_path, 'r')
        local new_script_parts = {}
        if not script then break end
        for line in script:lines() do
            for k, v in pairs(mode.settings) do
                if line:match(k .. "%s*=") then
                    line = k .. " = " .. v
                    break
                end
            end
            table.insert(new_script_parts, line)
        end
        script:close()
        local new_script = io.open(script_path, 'w')
        if not new_script then break end
        new_script:write(table.concat(new_script_parts, "\n"))
        new_script:close()
    end
    for i, mode in ipairs(vs.state) do
        mp.commandv("vf", "add", "@VS" .. i .. ":vapoursynth:file=" .. vs.modes[mode].path)
    end
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
    if not vs.state then
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
        '-x265-params "colorprim=%s:colormatrix=%s:transfer=%s:range=%s" ',
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
        'cmd /c "cd /d %q & vspipe -c y4m %q - -p | ffmpeg -y -hide_banner -loglevel error -thread_queue_size 2048 -i - -i %q -map 0:v -map 1:a? -map 1:s? -map 1:t? -map 1:d? -c:v libx265 -crf 18 -pix_fmt p010 %s-c:a copy -c:s copy -c:t copy -c:d copy %q & pause"',
        esc(mpv_path), esc(vpy_path), esc(video_path), x265_params, esc(output_path)
    )
    os.execute(cmd)
    os.remove(video_path .. ".lwi")
end

local function init(_, loaded)
    if not loaded then return end
    VS_Checked = io.open(mp.command_native({ "expand-path", "~~/../VSPipe.exe" })) and true or false
    mp.set_property_native("user-data/vs_checked", VS_Checked)
    if not VS_Checked then
        mp.msg.warn("未检测到VapourSynth，VS相关功能已禁用")
        mp.unregister_script_message("select_vs_mode")
        mp.unregister_script_message("vs_model_set")
        mp.remove_key_binding("vs_process_video")
        return
    end
    local saved = mp.get_property_native("user-data/vs")
    if saved then vs = saved end
    update()
    mp.register_script_message("select_vs_mode", function(value)
        if value == 'nil' then
            clear()
            vs.state = {}
            mp.osd_message("VS: nil")
        else
            table.insert(vs.state, value)
            local tags = {}
            for _, mode in ipairs(vs.state) do table.insert(tags, vs.modes[mode].label) end
            mp.osd_message("VS: " .. table.concat(tags, " >> "))
        end
        update()
    end)
    mp.register_script_message("set_vs_mode", function(name, key, value)
        if Watting then Watting:kill() end
        Watting = mp.add_timeout(0.5, update)
        clear()
        vs.modes[name].settings[key] = value
    end)
    mp.register_script_message("toggle_vs_preset", function()
        vs.preset = not vs.preset
        update()
    end)
    mp.add_key_binding(nil, "vs_process_video", encode_video)
    mp.unobserve_property(init)
end

mp.observe_property("user-data/__state_loaded__", "bool", init)
