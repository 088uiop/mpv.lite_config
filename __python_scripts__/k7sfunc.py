import vapoursynth as vs
import vsmlrt


def FMT_DSCALE(
    input: vs.VideoNode,
    w_pre: int = 0,
    h_pre: int = 0,
    lk_fmt: bool = False,
) -> vs.VideoNode:
    w_in, h_in = input.width, input.height
    fmt_out = vs.YUV420P8 if lk_fmt else input.format.id

    def _ensure_even(x):
        return x if x % 2 == 0 else x - 1

    clip = input
    if fmt_out != input.format.id or w_in % 2 != 0 or h_in % 2 != 0:
        clip = vs.core.resize.Bilinear(
            clip, width=_ensure_even(w_in), height=_ensure_even(h_in), format=fmt_out
        )
    if w_pre > 0 or h_pre > 0:
        ratio = w_in / h_in
        nw, nh = w_in, h_in
        if w_pre > 0 and h_pre > 0 and ratio > (w_pre / h_pre) and w_in > w_pre:
            nw, nh = w_pre, round(w_pre / ratio)
        elif h_pre > 0 and h_in > h_pre:
            nh, nw = h_pre, round(h_pre * ratio)
        elif w_pre > 0 and w_in > w_pre:
            nw, nh = w_pre, round(w_pre / ratio)
        nw, nh = _ensure_even(nw), _ensure_even(nh)
        if (nw, nh) != (clip.width, clip.height):
            clip = vs.core.resize.Bicubic(
                clip, width=nw, height=nh, filter_param_a=1 / 3, filter_param_b=1 / 3
            )
    return clip


def FMT_LIMIT(
    input: vs.VideoNode,
    w_max: int = 1920,
    h_max: int = 1080,
) -> vs.VideoNode:
    if input.width > w_max or input.height > h_max:
        raise Exception("源分辨率超过限制范围")
    return input


def FPS_LIMIT(
    input: vs.VideoNode,
    fps_in: float = 23.976,
    fps_max: float = 47.952,
) -> vs.VideoNode:
    if fps_in > fps_max:
        raise Exception("源帧率超过限制范围")
    return input


def SVP(
    input: vs.VideoNode,
    fps_in: float = 23.976,
    fps_num: int = 2,
    fps_den: int = 1,
    abs: bool = False,
    nvof: bool = False,
    gpu: int = 0,
) -> vs.VideoNode:
    if not hasattr(vs.core, "svp1") or not hasattr(vs.core, "svp2"):
        raise ModuleNotFoundError("缺失 SVP 插件")
    clip8 = (
        input
        if input.format.id == vs.YUV420P8
        else vs.core.resize.Bilinear(input, format=vs.YUV420P8)
    )
    clipw = (
        input
        if input.format.id in [vs.YUV420P8, vs.YUV420P10]
        else vs.core.resize.Bilinear(input, format=vs.YUV420P10)
    )
    size_in = input.width * input.height
    ana_lv = 5 if size_in > 510272 else 2
    s_sup = "{pel:1,gpu:%d,full:true,scale:{up:2,down:4}}" % gpu
    s_ana = (
        "{vectors:3,block:{w:32,h:32,overlap:1},main:{levels:%d,search:{type:4,distance:3,sort:true}}}"
        % ana_lv
    )
    s_sm = (
        "{rate:{num:%d,den:%d,abs:%s},algo:13,gpuid:%d,linear:true,scene:{mode:3}}"
        % (fps_num, fps_den, "true" if abs else "false", gpu)
    )
    if nvof:
        return vs.core.svp2.SmoothFps_NVOF(
            clipw, s_sm, nvof_src=clip8, src=clipw, fps=fps_in
        )
    sd = vs.core.svp1.Super(clip8, s_sup)
    vec = vs.core.svp1.Analyse(sd["clip"], sd["data"], clipw, s_ana)
    return vs.core.svp2.SmoothFps(
        clip8,
        sd["clip"],
        sd["data"],
        vec["clip"],
        vec["data"],
        s_sm,
        src=clipw,
        fps=fps_in,
    )


def get_backend(
    w_in: int = 0,
    h_in: int = 0,
    be: str = "ort_dml",
    gpu: int = 0,
    static: bool = True,
):
    if not static and (w_in < 384 or h_in < 384 or w_in > 4096 or h_in > 2176):
        raise Exception("源分辨率不属于动态引擎支持的范围")
    backend_configs = {
        "ort_dml": lambda: vsmlrt.BackendV2.ORT_DML(
            num_streams=2,
            fp16=True,
            output_format=1,
            device_id=gpu,
        ),
        "trt": lambda: vsmlrt.BackendV2.TRT(
            num_streams=2,
            fp16=True,
            output_format=1,
            static_shape=static,
            min_shapes=[0, 0] if static else [384, 384],
            opt_shapes=None if static else [1920, 1152],
            max_shapes=None if static else [4096, 2176],
            use_cuda_graph=True,
            device_id=gpu,
        ),
        "trt_rtx": lambda: vsmlrt.BackendV2.TRT_RTX(
            num_streams=2,
            fp16=True,
            output_format=1,
            static_shape=static,
            min_shapes=[0, 0] if static else [384, 384],
            opt_shapes=None if static else [1920, 1152],
            max_shapes=None if static else [4096, 2176],
            use_cuda_graph=True,
            device_id=gpu,
        ),
    }
    return backend_configs[be]()


def RIFE(
    input: vs.VideoNode,
    fps_in: float = 23.976,
    be: str = "ort_dml",
    model: int = 46,
    abs: bool = False,
    fps_num: int = 2,
    fps_den: int = 1,
    sc_mode: bool = True,
    gpu: int = 0,
    static: bool = True,
) -> vs.VideoNode:
    import fractions

    fmt_in = input.format.id
    colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
    clip = vs.core.misc.SCDetect(clip=input, threshold=0.15) if sc_mode else input
    clip = vs.core.resize.Bilinear(clip, format=vs.RGBH, matrix_in_s="709")
    if abs:
        fpsin = fractions.Fraction(fps_in)
        fps_num *= fpsin.denominator
        fps_den *= fpsin.numerator
    fpsout = fractions.Fraction(fps_num, fps_den).limit_denominator(10)
    fps_num = fpsout.numerator
    fps_den = fpsout.denominator
    fin = vsmlrt.RIFE(
        clip=clip,
        multi=fractions.Fraction(fps_num, fps_den),
        model=model,
        video_player=True,
        _implementation=2,
        backend=get_backend(
            w_in=input.width,
            h_in=input.height,
            be=be,
            gpu=gpu,
            static=static,
        ),
    )
    out = vs.core.resize.Bilinear(
        fin, format=fmt_in, matrix_s="709", range=1 if colorlv == 0 else None
    )
    return out.std.AssumeFPS(fpsnum=fps_in * fps_num * 1e7, fpsden=fps_den * 1e7)


def DRBA(
    input: vs.VideoNode,
    fps_in: float = 23.976,
    be: str = "ort_dml",
    model: int = 2,
    abs: bool = False,
    fps_num: int = 2,
    fps_den: int = 1,
    sc_mode: bool = True,
    gpu: int = 0,
    static: bool = True,
) -> vs.VideoNode:
    import fractions

    fmt_in = input.format.id
    colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
    clip = vs.core.misc.SCDetect(clip=input, threshold=0.15) if sc_mode else input
    clip = vs.core.resize.Bilinear(clip, format=vs.RGBH, matrix_in_s="709")
    if abs:
        fpsin = fractions.Fraction(fps_in)
        fps_num *= fpsin.denominator
        fps_den *= fpsin.numerator
    fpsout = fractions.Fraction(fps_num, fps_den).limit_denominator(10)
    fps_num = fpsout.numerator
    fps_den = fpsout.denominator
    fin = vsmlrt.DRBA(
        clip=clip,
        multi=fractions.Fraction(fps_num, fps_den),
        ap=True,
        model=model,
        video_player=True,
        backend=get_backend(
            w_in=input.width,
            h_in=input.height,
            be=be,
            gpu=gpu,
            static=static,
        ),
    )
    out = vs.core.resize.Bilinear(
        fin, format=fmt_in, matrix_s="709", range=1 if colorlv == 0 else None
    )
    return out.std.AssumeFPS(fpsnum=fps_in * fps_num * 1e7, fpsden=fps_den * 1e7)


def RealESRGAN(
    input: vs.VideoNode,
    be: str = "ort_dml",
    model: int = 5008,
    gpu: int = 0,
    static: bool = True,
) -> vs.VideoNode:
    fmt_in = input.format.id
    colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
    clip = vs.core.resize.Bilinear(input, format=vs.RGBH, matrix_in_s="709")
    res = vsmlrt.RealESRGAN(
        clip=clip,
        model=model,
        backend=get_backend(
            w_in=input.width,
            h_in=input.height,
            be=be,
            gpu=gpu,
            static=static,
        ),
    )
    return vs.core.resize.Bilinear(
        res, format=fmt_in, matrix_s="709", range=1 if colorlv == 0 else None
    )


def UAI(
    input: vs.VideoNode,
    be: str = "ort_dml",
    model_pth: str = "",
    gpu: int = 0,
    static: bool = True,
) -> vs.VideoNode:
    import os
    import onnx

    fmt_in = input.format.id
    colorlv = getattr(input.get_frame(0).props, "_ColorRange", 0)
    be_lower = be.lower()
    if be_lower in ["trt", "trt_rtx"]:
        plg_dir = os.path.dirname(
            vs.core.trt_rtx.Version()["path"]
            if be_lower == "trt_rtx"
            else vs.core.trt.Version()["path"]
        ).decode()
    else:
        plg_dir = os.path.dirname(vs.core.ort.Version()["path"]).decode()
    mdl_pth_rel = plg_dir + "/models/uai/" + model_pth
    mdl_pth = mdl_pth_rel if os.path.exists(mdl_pth_rel) else model_pth
    model = onnx.load(mdl_pth)
    shape = []
    for dim in model.graph.input[0].type.tensor_type.shape.dim:
        if dim.dim_param:
            shape.append(-1)
        else:
            shape.append(dim.dim_value if dim.dim_value > 0 else -1)
    if shape[1] == 1:
        clip_y = vs.core.resize.Point(clip=input, format=vs.GRAYH)
        infer = vsmlrt.inference(
            clips=clip_y,
            network_path=mdl_pth,
            backend=get_backend(
                w_in=input.width,
                h_in=input.height,
                be=be,
                gpu=gpu,
                static=static,
            ),
        )
        clip_uv = vs.core.resize.Bilinear(clip=input, format=vs.YUV444PH)
        output = vs.core.std.ShufflePlanes([infer, clip_uv], [0, 1, 2], vs.YUV)
        output = vs.core.resize.Bilinear(
            clip=output, format=fmt_in, range=1 if colorlv == 0 else None
        )
        return output
    else:
        clip = vs.core.resize.Bilinear(clip=input, format=vs.RGBH, matrix_in_s="709")
        infer = vsmlrt.inference(
            clips=clip,
            network_path=mdl_pth,
            backend=get_backend(
                w_in=input.width,
                h_in=input.height,
                be=be,
                gpu=gpu,
                static=static,
            ),
        )
        return vs.core.resize.Bilinear(
            clip=infer, format=fmt_in, matrix_s="709", range=1 if colorlv == 0 else None
        )
