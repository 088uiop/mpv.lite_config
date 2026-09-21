__version__ = "3.23.2"

__all__ = [
    "Backend", "BackendV2",
    "RealESRGAN", "RealESRGANModel",
    "RIFE", "RIFEModel", "RIFEMerge",
    "DRBA", "DRBAModel", "DRBAMerge",
    "inference",
    "flexible_inference"
]

import copy
from dataclasses import dataclass, field
import enum
from fractions import Fraction
import math
import os
import os.path
import platform
import subprocess
import sys
import tempfile
import time
import typing
import zlib

import vapoursynth as vs
from vapoursynth import core


def get_plugins_path() -> str:
    plugin_names = ("ort", "trt", "trt_rtx")

    for plugin_name in plugin_names:
        try:
            path = getattr(core, plugin_name).Version()["path"]
            return os.path.dirname(path).decode()
        except AttributeError:
            continue

    raise RuntimeError("vsmlrt: cannot load any filters")


plugins_path: str = get_plugins_path()
trtexec_path: str = os.path.join(plugins_path, "vsmlrt-cuda", "trtexec")
tensorrt_rtx_path: str = os.path.join(plugins_path, "vsmlrt-cuda", "tensorrt_rtx")
models_path: str = os.path.join(plugins_path, "models")


class Backend:
    @dataclass(frozen=False)
    class TRT:
        """ backend for nvidia gpus (TensorRT 11+) """

        max_shapes: typing.Optional[typing.Tuple[int, int]] = None
        opt_shapes: typing.Optional[typing.Tuple[int, int]] = None
        device_id: int = 0
        workspace: typing.Optional[int] = None
        verbose: bool = False
        use_cuda_graph: bool = True
        num_streams: int = 1
        static_shape: bool = True
        log: bool = True
        use_edge_mask_convolutions: bool = True
        use_jit_convolutions: bool = True
        min_shapes: typing.Tuple[int, int] = (0, 0)
        builder_optimization_level: int = 3
        max_aux_streams: typing.Optional[int] = None
        short_path: typing.Optional[bool] = None  # True on Windows by default, False otherwise
        custom_env: typing.Dict[str, str] = field(default_factory=lambda: {})
        custom_args: typing.List[str] = field(default_factory=lambda: [])
        engine_folder: typing.Optional[str] = None
        max_tactics: typing.Optional[int] = None
        tiling_optimization_level: int = 0
        l2_limit_for_tiling: int = -1

        # internal backend attributes
        supports_onnx_serialization: bool = False

    @dataclass(frozen=False)
    class TRT_RTX:
        """ backend for nvidia rtx gpus (TensorRT-RTX) """

        device_id: int = 0
        workspace: typing.Optional[int] = None
        verbose: bool = False
        use_cuda_graph: bool = False
        num_streams: int = 1

        static_shape: bool = True
        min_shapes: typing.Tuple[int, int] = (0, 0)
        opt_shapes: typing.Optional[typing.Tuple[int, int]] = None
        max_shapes: typing.Optional[typing.Tuple[int, int]] = None

        use_edge_mask_convolutions: bool = True
        builder_optimization_level: int = 3
        max_aux_streams: typing.Optional[int] = None
        short_path: typing.Optional[bool] = None  # True on Windows by default, False otherwise
        custom_env: typing.Dict[str, str] = field(default_factory=lambda: {})
        custom_args: typing.List[str] = field(default_factory=lambda: [])
        engine_folder: typing.Optional[str] = None
        max_tactics: typing.Optional[int] = None
        tiling_optimization_level: int = 0
        l2_limit_for_tiling: int = -1

        # internal backend attributes
        supports_onnx_serialization: bool = False

    @dataclass(frozen=False)
    class ORT_DML:
        """ backend for directml (d3d12) devices """

        device_id: int = 0
        num_streams: int = 1
        verbosity: int = 2
        output_format: int = 0  # 0: fp32, 1: fp16

        # internal backend attributes
        supports_onnx_serialization: bool = True


backendT = typing.Union[
    Backend.TRT,
    Backend.TRT_RTX,
    Backend.ORT_DML,
]


fallback_backend: typing.Optional[backendT] = None


def _resolve_model(
    network_path: typing.Union[bytes, str],
    fp16: bool,
    int8: bool,
) -> typing.Tuple[typing.Union[bytes, str], bool]:
    """Select the offline-converted model file for the requested precision.

    Returns (path, fp16_io). fp16_io is True when the chosen model has fp16 IO
    (so the ORT backend sets output_format = 1).

    If both fp16 and int8 are True, fp16 wins.
    """
    if not isinstance(network_path, str):
        return network_path, False
    if fp16:
        return network_path[:-5] + "_fp16.onnx", True
    elif int8:
        return network_path[:-5] + "_int8.onnx", True
    return network_path, False


def _set_output_format(backend: backendT, fp16_io: bool) -> backendT:
    if isinstance(backend, Backend.ORT_DML):
        backend.output_format = 1 if fp16_io else 0
    return backend


@enum.unique
class RealESRGANModel(enum.IntEnum):
    # v3
    animevideov3 = 2  # 4x
    # contributed: janaiV3-hd(2x) https://github.com/the-database/mpv-upscale-2x_animejanai/releases/tag/3.0.0
    animejanaiV3_HD_L1 = 5008
    animejanaiV3_HD_L2 = 5009
    animejanaiV3_HD_L3 = 5010
    # contributed: Ani4K-v2 https://github.com/Sirosky/Upscale-Hub/releases/tag/Ani4K-v2
    Ani4Kv2_G6i2_Compact = 7000
    Ani4Kv2_G6i2_UltraCompact = 7001


def RealESRGAN(
    clip: vs.VideoNode,
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    overlap: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    model: RealESRGANModel = RealESRGANModel.animejanaiV3_HD_L1,
    backend: backendT = Backend.ORT_DML(),
    scale: typing.Optional[float] = None,
    fp16: bool = False,
    int8: bool = False,
) -> vs.VideoNode:

    func_name = "vsmlrt.RealESRGAN"

    if not isinstance(clip, vs.VideoNode):
        raise TypeError(f'{func_name}: "clip" must be a clip!')

    if clip.format.sample_type != vs.FLOAT or clip.format.bits_per_sample not in [16, 32]:
        raise ValueError(f"{func_name}: only constant format 16/32 bit float input supported")

    if clip.format.color_family != vs.RGB:
        raise ValueError(f'{func_name}: "clip" must be of RGB color family')

    if not isinstance(model, int) or model not in RealESRGANModel.__members__.values():
        raise ValueError(f'{func_name}: invalid "model"')

    if overlap is None:
        overlap_w = overlap_h = 8
    elif isinstance(overlap, int):
        overlap_w = overlap_h = overlap
    else:
        overlap_w, overlap_h = overlap

    multiple = 1

    (tile_w, tile_h), (overlap_w, overlap_h) = calc_tilesize(
        tiles=tiles, tilesize=tilesize,
        width=clip.width, height=clip.height,
        multiple=multiple,
        overlap_w=overlap_w, overlap_h=overlap_h
    )

    if tile_w % multiple != 0 or tile_h % multiple != 0:
        raise ValueError(
            f'{func_name}: tile size must be divisible by {multiple} ({tile_w}, {tile_h})'
        )

    backend = init_backend(
        backend=backend,
        trt_opt_shapes=(tile_w, tile_h)
    )

    if model == 2:
        network_path = os.path.join(
            models_path,
            "realesrgan",
            "realesr-animevideov3.onnx"
        )
    else:
        network_path = os.path.join(
            models_path,
            "realesrgan",
            f"{RealESRGANModel(model).name}.onnx".replace('_', '-')
        )

    network_path, fp16_io = _resolve_model(network_path, fp16, int8)
    backend = _set_output_format(backend, fp16_io)

    clip_org = clip
    clip = inference_with_fallback(
        clips=[clip], network_path=network_path,
        overlap=(overlap_w, overlap_h), tilesize=(tile_w, tile_h),
        backend=backend
    )

    if scale is not None:
        scale_h = clip.width // clip_org.width
        scale_v = clip.height // clip_org.height

        assert scale_h == scale_v

        if scale != scale_h:
            rescale = scale / scale_h

            if rescale > 1:
                clip = core.resize.Lanczos(clip, int(clip_org.width * scale), int(clip_org.height * scale), filter_param_a=4)
            else:
                clip = fmtc_resample(clip, scale=rescale, kernel="lanczos", taps=4, fh=1/rescale, fv=1/rescale)

    return clip


@enum.unique
class RIFEModel(enum.IntEnum):
    v4_6 = 46
    v4_25_lite = 4251
    v4_26 = 426
    v4_26_heavy = 4262


def RIFEMerge(
    clipa: vs.VideoNode,
    clipb: vs.VideoNode,
    mask: vs.VideoNode,
    scale: float = 1.0,
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    overlap: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    model: RIFEModel = RIFEModel.v4_6,
    backend: backendT = Backend.ORT_DML(),
    ensemble: bool = False,
    fp16: bool = False,
    int8: bool = False,
) -> vs.VideoNode:
    """ temporal MaskedMerge-like interface for the RIFE model (v2 format only)

    Its semantics is similar to core.std.MaskedMerge(clipa, clipb, mask, first_plane=True),
    except that it merges the two clips in the time domain and you specify the "mask" based
    on the time point of the resulting clip (range (0,1)) between the two clips.
    """

    func_name = "vsmlrt.RIFEMerge"

    for clip in (clipa, clipb, mask):
        if not isinstance(clip, vs.VideoNode):
            raise TypeError(f'{func_name}: clip must be a clip!')

        if clip.format.sample_type != vs.FLOAT or clip.format.bits_per_sample not in [16, 32]:
            raise ValueError(f"{func_name}: only constant format 16/32 bit float input supported")

    for clip in (clipa, clipb):
        if clip.format.color_family != vs.RGB:
            raise ValueError(f'{func_name}: "clipa" / "clipb" must be of RGB color family')

        if clip.width != mask.width or clip.height != mask.height:
            raise ValueError(f'{func_name}: video dimensions mismatch')

        if clip.num_frames != mask.num_frames:
            raise ValueError(f'{func_name}: number of frames mismatch')

    if mask.format.color_family != vs.GRAY:
        raise ValueError(f'{func_name}: "mask" must be of GRAY color family')

    if tiles is not None or tilesize is not None or overlap is not None:
        raise ValueError(f'{func_name}: tiling is not supported')

    if scale != 1.0:
        raise ValueError(f'{func_name}: "scale" must be 1.0 (v2 format only supports scale 1.0)')

    overlap_w = overlap_h = 0
    multiple = 1  # v2 implements internal padding

    version = RIFEModel(model).name.replace("_", ".", 1) + ("_ensemble" if ensemble else "")

    network_path = os.path.join(
        models_path,
        "rife",
        f"rife_{version}.onnx"
    )
    clips = [clipa, clipb, mask]

    (tile_w, tile_h), (overlap_w, overlap_h) = calc_tilesize(
        tiles=tiles, tilesize=tilesize,
        width=clipa.width, height=clipa.height,
        multiple=multiple,
        overlap_w=overlap_w, overlap_h=overlap_h
    )

    if tile_w % multiple != 0 or tile_h % multiple != 0:
        raise ValueError(
            f'{func_name}: tile size must be divisible by {multiple} ({tile_w}, {tile_h})'
        )

    backend = init_backend(
        backend=backend,
        trt_opt_shapes=(tile_w, tile_h)
    )

    network_path, fp16_io = _resolve_model(network_path, fp16, int8)
    backend = _set_output_format(backend, fp16_io)

    return inference_with_fallback(
        clips=clips, network_path=network_path,
        overlap=(overlap_w, overlap_h), tilesize=(tile_w, tile_h),
        backend=backend
    )


def RIFE(
    clip: vs.VideoNode,
    multi: typing.Union[int, Fraction] = 2,
    scale: float = 1.0,
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    overlap: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    model: RIFEModel = RIFEModel.v4_6,
    backend: backendT = Backend.ORT_DML(),
    ensemble: bool = False,
    video_player: bool = False,
    fp16: bool = False,
    int8: bool = False,
) -> vs.VideoNode:
    """ RIFE: Real-Time Intermediate Flow Estimation for Video Frame Interpolation

    multi, scale is based on vs-rife.

    For the best results, you need to perform scene detection on the input clip
    (e.g. misc.SCDetect, mv.SCDetection) before passing it to RIFE.
    Also note that the quality of result is strongly dependent on high quality
    scene detection and you might need to tweak the scene detection parameters
    and/or filter to achieve the best quality.

    Args:
        multi: Multiple of the frame counts, can be a fractions.Fraction.
            Default: 2.

        scale: Controls the process resolution for optical flow model.
            v2 format only supports scale = 1.0.
    """

    func_name = "vsmlrt.RIFE"

    if not isinstance(clip, vs.VideoNode):
        raise TypeError(f'{func_name}: "clip" must be a clip!')

    if clip.format.sample_type != vs.FLOAT or clip.format.bits_per_sample not in [16, 32]:
        raise ValueError(f"{func_name}: only constant format 16/32 bit float input supported")

    if clip.format.color_family != vs.RGB:
        raise ValueError(f'{func_name}: "clip" must be of RGB color family')

    if not isinstance(multi, (int, Fraction)):
        raise TypeError(f'{func_name}: "multi" must be an integer or a fractions.Fraction!')

    if tiles is not None or tilesize is not None or overlap is not None:
        raise ValueError(f'{func_name}: tiling is not supported')

    gray_format = vs.GRAYS if clip.format.bits_per_sample == 32 else vs.GRAYH

    if int(multi) == multi:
        multi = int(multi)

        if multi < 2:
            raise ValueError(f'{func_name}: RIFE: multi must be at least 2')

        initial = core.std.Interleave([clip] * (multi - 1))

        terminal = clip.std.DuplicateFrames(frames=clip.num_frames - 1).std.Trim(first=1)
        terminal = core.std.Interleave([terminal] * (multi - 1))

        timepoint = core.std.Interleave([
            clip.std.BlankClip(format=gray_format, color=i/multi, length=1)
            for i in range(1, multi)
        ]).std.Loop(clip.num_frames)

        output0 = RIFEMerge(
            clipa=initial, clipb=terminal, mask=timepoint,
            scale=scale, tiles=tiles, tilesize=tilesize, overlap=overlap,
            model=model, backend=backend, ensemble=ensemble,
            fp16=fp16, int8=int8
        )

        clip = bits_as(clip, output0)
        initial = core.std.Interleave([clip] * (multi - 1))

        if hasattr(core, 'akarin') and hasattr(core.akarin, 'Select'):
            output = core.akarin.Select([output0, initial], initial, 'x._SceneChangeNext 1 0 ?')
        else:
            def handler(n: int, f: vs.VideoFrame) -> vs.VideoNode:
                if f.props.get('_SceneChangeNext'):
                    return initial
                return output0
            output = core.std.FrameEval(output0, handler, initial)

        if multi == 2:
            res = core.std.Interleave([clip, output])
        else:
            res = core.std.Interleave([
                clip,
                *(output.std.SelectEvery(cycle=multi-1, offsets=i) for i in range(multi - 1))
            ])

        if clip.fps_num != 0 and clip.fps_den != 0:
            return res.std.AssumeFPS(fpsnum = clip.fps_num * multi, fpsden = clip.fps_den)
        else:
            return res
    else:
        if clip.fps_num == 0 or clip.fps_den == 0:
            src_fps = Fraction(1)
        else:
            src_fps = clip.fps

        dst_fps = src_fps * multi
        src_frames = clip.num_frames
        dst_frames = min(int(src_frames * multi), 2 ** 31 - 1)

        duration_rel = src_fps / dst_fps
        dst_duration = duration_rel.numerator
        src_duration = duration_rel.denominator

        # https://github.com/AmusementClub/vs-mlrt/issues/59#issuecomment-1842649342
        if video_player:
            temp = core.std.BlankClip(clip, length=dst_frames, keep=True)

            def left_func(n: int) -> vs.VideoNode:
                return clip[dst_duration * n // src_duration]
            left_clip = core.std.FrameEval(temp, left_func)

            def right_func(n: int) -> vs.VideoNode:
                # no out of range access because of function filter_sc
                return clip[dst_duration * n // src_duration + 1]
            right_clip = core.std.FrameEval(temp, right_func)

            temp_gray = core.std.BlankClip(temp, format=gray_format, keep=True)
            def timepoint_func(n: int) -> vs.VideoNode:
                current_time = dst_duration * n
                left_index = current_time // src_duration
                left_time = src_duration * left_index
                tp = (current_time - left_time) / src_duration
                return temp_gray.std.BlankClip(color=tp, keep=True)
            tp_clip = core.std.FrameEval(temp_gray, timepoint_func)

            output0 = RIFEMerge(
                clipa=left_clip, clipb=right_clip, mask=tp_clip,
                scale=scale, tiles=tiles, tilesize=tilesize, overlap=overlap,
                model=model, backend=backend, ensemble=ensemble,
                fp16=fp16, int8=int8
            )

            left0 = bits_as(left_clip, output0)

            def filter_sc(n: int, f: vs.VideoFrame) -> vs.VideoNode:
                current_time = dst_duration * n
                left_index = current_time // src_duration
                if (
                    current_time % src_duration == 0 or
                    left_index + 1 >= src_frames or
                    f.props.get("_SceneChangeNext", False)
                ):
                    return left0
                else:
                    return output0

            res = core.std.FrameEval(output0, filter_sc, left0)
        else:
            if not hasattr(core, 'akarin') or \
                not hasattr(core.akarin, 'PropExpr') or \
                not hasattr(core.akarin, 'PickFrames'):
                raise RuntimeError(
                    'fractional multi requires plugin akarin '
                    '(https://github.com/AkarinVS/vapoursynth-plugin/releases)'
                    ', version v0.96g or later.')

            left_indices = []
            right_indices = []
            timepoints = []
            output_indices = []

            for i in range(dst_frames):
                current_time = dst_duration * i
                if current_time % src_duration == 0:
                    output_indices.append(current_time // src_duration)
                else:
                    left_index = current_time // src_duration
                    if left_index + 1 >= src_frames:
                        # approximate last frame with last frame of source
                        output_indices.append(src_frames - 1)
                        break
                    output_indices.append(src_frames + len(timepoints))
                    left_indices.append(left_index)
                    right_indices.append(left_index + 1)
                    left_time = src_duration * left_index
                    tp = (current_time - left_time) / src_duration
                    timepoints.append(tp)

            left_clip = core.akarin.PickFrames(clip, left_indices)
            right_clip = core.akarin.PickFrames(clip, right_indices)
            tp_clip = core.std.BlankClip(clip, format=gray_format, length=len(timepoints))
            tp_clip = tp_clip.akarin.PropExpr(lambda: dict(_tp=timepoints)).akarin.Expr('x._tp')

            output0 = RIFEMerge(
                clipa=left_clip, clipb=right_clip, mask=tp_clip,
                scale=scale, tiles=tiles, tilesize=tilesize, overlap=overlap,
                model=model, backend=backend, ensemble=ensemble,
                fp16=fp16, int8=int8
            )

            clip0 = bits_as(clip, output0)
            left0 = bits_as(left_clip, output0)
            output = core.akarin.Select([output0, left0], left0, 'x._SceneChangeNext 1 0 ?')
            res = core.akarin.PickFrames(clip0 + output, output_indices)

        if clip.fps_num != 0 and clip.fps_den != 0:
            return res.std.AssumeFPS(fpsnum = dst_fps.numerator, fpsden = dst_fps.denominator)
        else:
            return res


@enum.unique
class DRBAModel(enum.IntEnum):
    v1 = 1
    v2_lite = 2


def DRBAMerge(
    clip0: vs.VideoNode,
    clip1: vs.VideoNode,
    clip2: vs.VideoNode,
    clip3: vs.VideoNode,
    mask: vs.VideoNode,
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    overlap: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    model: DRBAModel = DRBAModel.v1,
    backend: backendT = Backend.ORT_DML(),
    fp16: bool = False,
    int8: bool = False,
) -> vs.VideoNode:
    """ DRBA (auto-padding variant only) """

    func_name = "vsmlrt.DRBAMerge"

    for clip in (clip0, clip1, clip2, clip3, mask):
        if not isinstance(clip, vs.VideoNode):
            raise TypeError(f'{func_name}: all inputs must be clips!')

        if clip.format.sample_type != vs.FLOAT or clip.format.bits_per_sample not in [16, 32]:
            raise ValueError(f"{func_name}: only constant format 16/32 bit float input supported")

    for clip in (clip0, clip1, clip2, clip3):
        if clip.format.color_family != vs.RGB:
            raise ValueError(f'{func_name}: frame clips must be RGB color family')

        if clip.width != mask.width or clip.height != mask.height:
            raise ValueError(f'{func_name}: video dimensions mismatch')

        if clip.num_frames != mask.num_frames:
            raise ValueError(f'{func_name}: number of frames mismatch')

    if mask.format.color_family != vs.GRAY:
        raise ValueError(f'{func_name}: "mask" must be of GRAY color family')

    if tiles is not None or tilesize is not None or overlap is not None:
        raise ValueError(f'{func_name}: tiling is not supported')

    overlap_w = overlap_h = 0

    # auto-padding variants use internal padding
    multiple = 1

    if model == DRBAModel.v1:
        version = "v1"
    elif model == DRBAModel.v2_lite:
        version = "v2_lite"
    else:
        raise ValueError(f'{func_name}: unsupported model version')

    model_name = f"distilDRBA_{version}.onnx"

    network_path = os.path.join(
        models_path,
        "drba",
        model_name
    )

    gray_format = vs.GRAYS if clip0.format.bits_per_sample == 32 else vs.GRAYH
    scale_placeholder = clip0.std.BlankClip(format=gray_format, color=1.0, keep=True)

    clips = [clip0, clip1, clip2, clip3, mask, scale_placeholder]

    (tile_w, tile_h), (overlap_w, overlap_h) = calc_tilesize(
        tiles=tiles, tilesize=tilesize,
        width=clip0.width, height=clip0.height,
        multiple=multiple,
        overlap_w=overlap_w, overlap_h=overlap_h
    )

    backend = init_backend(
        backend=backend,
        trt_opt_shapes=(tile_w, tile_h)
    )

    network_path, fp16_io = _resolve_model(network_path, fp16, int8)
    backend = _set_output_format(backend, fp16_io)

    return inference_with_fallback(
        clips=clips, network_path=network_path,
        overlap=(overlap_w, overlap_h), tilesize=(tile_w, tile_h),
        backend=backend
    )


def DRBA(
    clip: vs.VideoNode,
    multi: typing.Union[int, Fraction] = 2,
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    overlap: typing.Optional[typing.Union[int, typing.Tuple[int, int]]] = None,
    model: DRBAModel = DRBAModel.v1,
    backend: backendT = Backend.ORT_DML(),
    video_player: bool = False,
    fp16: bool = False,
    int8: bool = False,
) -> vs.VideoNode:
    """ DRBA:

    Args:
        multi: Multiple of the frame counts (2 for 2x, etc.)
    """

    func_name = "vsmlrt.DRBA"

    if not isinstance(clip, vs.VideoNode):
        raise TypeError(f'{func_name}: "clip" must be a clip!')

    if clip.format.sample_type != vs.FLOAT or clip.format.bits_per_sample not in [16, 32]:
        raise ValueError(f"{func_name}: only constant format 16/32 bit float input supported")

    if clip.format.color_family != vs.RGB:
        raise ValueError(f'{func_name}: "clip" must be of RGB color family')

    if not isinstance(multi, (int, Fraction)):
        raise TypeError(f'{func_name}: "multi" must be an integer or a fractions.Fraction!')

    if tiles is not None or tilesize is not None or overlap is not None:
        raise ValueError(f'{func_name}: tiling is not supported')

    gray_format = vs.GRAYS if clip.format.bits_per_sample == 32 else vs.GRAYH

    if int(multi) == multi:
        multi = int(multi)

        if multi < 2:
            raise ValueError(f'{func_name}: multi must be at least 2')

        gray_format = vs.GRAYS if clip.format.bits_per_sample == 32 else vs.GRAYH
        n_frames = clip.num_frames

        if n_frames < 4:
            raise ValueError(f'{func_name}: clip must have at least 4 frames for DRBA')

        img1 = clip
        img2 = clip.std.DuplicateFrames(frames=n_frames - 1).std.Trim(first=1)
        img0 = clip.std.DuplicateFrames(frames=0).std.Trim(last=n_frames - 1)
        img3 = img2.std.DuplicateFrames(frames=n_frames - 1).std.Trim(first=1)

        cnt = multi - 1
        img0 = core.std.Interleave([img0] * cnt)
        img1 = core.std.Interleave([img1] * cnt)
        img2 = core.std.Interleave([img2] * cnt)
        img3 = core.std.Interleave([img3] * cnt)

        timepoint = core.std.Interleave([
            clip.std.BlankClip(format=gray_format, color=i/multi, length=1)
            for i in range(1, multi)
        ]).std.Loop(clip.num_frames)

        output0 = DRBAMerge(
            clip0=img0, clip1=img1, clip2=img2, clip3=img3, mask=timepoint,
            tiles=tiles, tilesize=tilesize, overlap=overlap,
            model=model, backend=backend,
            fp16=fp16, int8=int8
        )

        img1 = bits_as(img1, output0)

        # scene change
        if hasattr(core, 'akarin') and hasattr(core.akarin, 'Select'):
            interpolated = core.akarin.Select([output0, img1], img1, 'x._SceneChangeNext 1 0 ?')
        else:
            def handler(n: int, f: vs.VideoFrame) -> vs.VideoNode:
                if f.props.get('_SceneChangeNext'):
                    return img1
                return output0
            interpolated = core.std.FrameEval(output0, handler, img1)

        clip = bits_as(clip, output0)

        if multi == 2:
            res = core.std.Interleave([clip, interpolated])
        else:
            res = core.std.Interleave([
                clip,
                *(interpolated.std.SelectEvery(cycle=multi-1, offsets=i) for i in range(multi - 1))
            ])

        if clip.fps_num != 0 and clip.fps_den != 0:
            return res.std.AssumeFPS(fpsnum=clip.fps_num * multi, fpsden=clip.fps_den)
        else:
            return res
    else:
        if clip.fps_num == 0 or clip.fps_den == 0:
            src_fps = Fraction(1)
        else:
            src_fps = clip.fps

        dst_fps = src_fps * multi
        src_frames = clip.num_frames
        dst_frames = min(int(src_frames * multi), 2 ** 31 - 1)

        duration_rel = src_fps / dst_fps
        dst_duration = duration_rel.numerator
        src_duration = duration_rel.denominator

        if video_player:
            temp = core.std.BlankClip(clip, length=dst_frames, keep=True)

            def img0_func(n: int) -> vs.VideoNode:
                left_index = dst_duration * n // src_duration
                return clip[max(0, left_index - 1)]
            img0_clip = core.std.FrameEval(temp, img0_func)

            def img1_func(n: int) -> vs.VideoNode:
                return clip[dst_duration * n // src_duration]
            img1_clip = core.std.FrameEval(temp, img1_func)

            def img2_func(n: int) -> vs.VideoNode:
                # no out of range access because of function filter_sc
                return clip[dst_duration * n // src_duration + 1]
            img2_clip = core.std.FrameEval(temp, img2_func)

            def img3_func(n: int) -> vs.VideoNode:
                left_index = dst_duration * n // src_duration
                return clip[min(src_frames - 1, left_index + 2)]
            img3_clip = core.std.FrameEval(temp, img3_func)

            temp_gray = core.std.BlankClip(temp, format=gray_format, keep=True)
            def timepoint_func(n: int) -> vs.VideoNode:
                current_time = dst_duration * n
                left_index = current_time // src_duration
                left_time = src_duration * left_index
                tp = (current_time - left_time) / src_duration
                return temp_gray.std.BlankClip(color=tp, keep=True)
            tp_clip = core.std.FrameEval(temp_gray, timepoint_func)

            output0 = DRBAMerge(
                clip0=img0_clip, clip1=img1_clip, clip2=img2_clip, clip3=img3_clip, mask=tp_clip,
                tiles=tiles, tilesize=tilesize, overlap=overlap,
                model=model, backend=backend,
                fp16=fp16, int8=int8
            )

            left0 = bits_as(img1_clip, output0)

            def filter_sc(n: int, f: vs.VideoFrame) -> vs.VideoNode:
                current_time = dst_duration * n
                left_index = current_time // src_duration
                if (
                    current_time % src_duration == 0 or
                    left_index + 1 >= src_frames or
                    f.props.get("_SceneChangeNext", False)
                ):
                    return left0
                else:
                    return output0

            res = core.std.FrameEval(output0, filter_sc, left0)
        else:
            if not hasattr(core, 'akarin') or \
                not hasattr(core.akarin, 'PropExpr') or \
                not hasattr(core.akarin, 'PickFrames'):
                raise RuntimeError(
                    'fractional multi requires plugin akarin '
                    '(https://github.com/AkarinVS/vapoursynth-plugin/releases)'
                    ', version v0.96g or later.')

            img0_indices = []
            left_indices = []
            right_indices = []
            img3_indices = []
            timepoints = []
            output_indices = []

            for i in range(dst_frames):
                current_time = dst_duration * i
                if current_time % src_duration == 0:
                    output_indices.append(current_time // src_duration)
                else:
                    left_index = current_time // src_duration
                    if left_index + 1 >= src_frames:
                        # approximate last frame with last frame of source
                        output_indices.append(src_frames - 1)
                        break
                    output_indices.append(src_frames + len(timepoints))

                    left_indices.append(left_index)
                    right_indices.append(left_index + 1)
                    img0_indices.append(max(0, left_index - 1))
                    img3_indices.append(min(src_frames - 1, left_index + 2))

                    left_time = src_duration * left_index
                    tp = (current_time - left_time) / src_duration
                    timepoints.append(tp)

            img0 = core.akarin.PickFrames(clip, img0_indices)
            img1 = core.akarin.PickFrames(clip, left_indices)
            img2 = core.akarin.PickFrames(clip, right_indices)
            img3 = core.akarin.PickFrames(clip, img3_indices)

            tp_clip = core.std.BlankClip(clip, format=gray_format, length=len(timepoints))
            tp_clip = tp_clip.akarin.PropExpr(lambda: dict(_tp=timepoints)).akarin.Expr('x._tp')

            output0 = DRBAMerge(
                clip0=img0, clip1=img1, clip2=img2, clip3=img3, mask=tp_clip,
                tiles=tiles, tilesize=tilesize, overlap=overlap,
                model=model, backend=backend,
                fp16=fp16, int8=int8
            )

            clip0 = bits_as(clip, output0)
            left0 = bits_as(img1, output0)
            output = core.akarin.Select([output0, left0], left0, 'x._SceneChangeNext 1 0 ?')
            res = core.akarin.PickFrames(clip0 + output, output_indices)

        if clip.fps_num != 0 and clip.fps_den != 0:
            return res.std.AssumeFPS(fpsnum = dst_fps.numerator, fpsden = dst_fps.denominator)
        else:
            return res


def get_engine_path(
    network_path: str,
    min_shapes: typing.Tuple[int, int],
    opt_shapes: typing.Tuple[int, int],
    max_shapes: typing.Tuple[int, int],
    workspace: typing.Optional[int],
    static_shape: bool,
    builder_optimization_level: int,
    max_aux_streams: typing.Optional[int],
    short_path: typing.Optional[bool],
    engine_folder: typing.Optional[str],
    device_name: str = "",
    is_rtx: bool = False,
) -> str:

    with open(network_path, "rb") as file:
        checksum = zlib.adler32(file.read())

    if static_shape:
        shape_str = f"{opt_shapes[0]}x{opt_shapes[1]}"
    else:
        shape_str = (
            f"min{min_shapes[0]}x{min_shapes[1]}"
            f"_opt{opt_shapes[0]}x{opt_shapes[1]}"
            f"_max{max_shapes[0]}x{max_shapes[1]}"
        )

    identity = (
        shape_str +
        (f"_workspace{workspace}" if workspace is not None else "") +
        f"_opt{builder_optimization_level}" +
        (f"_max-aux-streams{max_aux_streams}" if max_aux_streams is not None else "") +
        f"_{device_name}" +
        ("_rtx" if is_rtx else "") +
        f"_{checksum:x}"
    )

    dirname, basename = os.path.split(network_path)

    if engine_folder is not None:
        os.makedirs(engine_folder, exist_ok=True)
        dirname = engine_folder

    use_short_path = False

    if short_path:
        use_short_path = True
    elif platform.system() == "Windows":
        # use short path by default
        if short_path is None:
            use_short_path = True
        # NTFS limitation
        elif len(f"{basename}.{identity}.engine.cache.lock") >= 256:
            use_short_path = True

    if use_short_path:
        return os.path.join(dirname, f"{zlib.crc32((f'{basename}.{identity}').encode()):x}.engine")
    else:
        return f"{os.path.join(dirname, basename)}.{identity}.engine"


def trtexec(
    network_path: str,
    channels: int,
    opt_shapes: typing.Tuple[int, int],
    max_shapes: typing.Tuple[int, int],
    device_id: int,
    workspace: typing.Optional[int] = None,
    verbose: bool = False,
    use_cuda_graph: bool = False,
    static_shape: bool = True,
    log: bool = False,
    use_edge_mask_convolutions: bool = True,
    use_jit_convolutions: bool = True,
    input_name: str = "input",
    min_shapes: typing.Tuple[int, int] = (0, 0),
    builder_optimization_level: int = 3,
    max_aux_streams: typing.Optional[int] = None,
    short_path: typing.Optional[bool] = None,
    custom_env: typing.Dict[str, str] = {},
    custom_args: typing.List[str] = [],
    engine_folder: typing.Optional[str] = None,
    max_tactics: typing.Optional[int] = None,
    tiling_optimization_level: int = 0,
    l2_limit_for_tiling: int = -1,
) -> str:

    if isinstance(opt_shapes, int):
        opt_shapes = (opt_shapes, opt_shapes)

    if isinstance(max_shapes, int):
        max_shapes = (max_shapes, max_shapes)

    try:
        device_name = core.trt.DeviceProperties(device_id)["name"].decode()
        device_name = device_name.replace(' ', '-')
    except AttributeError:
        device_name = f"device{device_id}"

    engine_path = get_engine_path(
        network_path=network_path,
        min_shapes=min_shapes,
        opt_shapes=opt_shapes,
        max_shapes=max_shapes,
        workspace=workspace,
        static_shape=static_shape,
        builder_optimization_level=builder_optimization_level,
        max_aux_streams=max_aux_streams,
        short_path=short_path,
        engine_folder=engine_folder,
        device_name=device_name,
    )

    if os.access(engine_path, mode=os.R_OK) and os.path.getsize(engine_path) >= 1024:
        return engine_path

    # do not consider alternative path when the engine_folder is given
    if engine_folder is None:
        alter_engine_path = os.path.join(
            tempfile.gettempdir(),
            os.path.splitdrive(engine_path)[1][1:]
        )

        if os.access(alter_engine_path, mode=os.R_OK) and os.path.getsize(alter_engine_path) >= 1024:
            return alter_engine_path

    try:
        # test writability
        with open(engine_path, "w") as f:
            pass
        os.remove(engine_path)
    except PermissionError:
        if engine_folder is None:
            print(f"{engine_path} is not writable", file=sys.stderr)
            engine_path = alter_engine_path
            dirname = os.path.dirname(engine_path)
            if not os.path.exists(dirname):
                os.makedirs(dirname)
            print(f"change engine path to {engine_path}", file=sys.stderr)
        else:
            # do not consider alternative path when the engine_folder is given
            raise PermissionError(f"{engine_path} is not writable")

    args = [
        trtexec_path,
        f"--onnx={network_path}",
        f"--timingCacheFile={engine_path}.cache",
        f"--device={device_id}",
        f"--saveEngine={engine_path}"
    ]

    if workspace is not None:
        args.append(f"--memPoolSize=workspace:{workspace}")

    if static_shape:
        args.append(f"--shapes={input_name}:1x{channels}x{opt_shapes[1]}x{opt_shapes[0]}")
    else:
        args.extend([
            f"--minShapes={input_name}:1x{channels}x{min_shapes[1]}x{min_shapes[0]}",
            f"--optShapes={input_name}:1x{channels}x{opt_shapes[1]}x{opt_shapes[0]}",
            f"--maxShapes={input_name}:1x{channels}x{max_shapes[1]}x{max_shapes[0]}"
        ])

    if verbose:
        args.append("--verbose")

    tactic_sources = []

    if use_edge_mask_convolutions:
        tactic_sources.append("+EDGE_MASK_CONVOLUTIONS")
    else:
        tactic_sources.append("-EDGE_MASK_CONVOLUTIONS")

    if use_jit_convolutions:
        tactic_sources.append("+JIT_CONVOLUTIONS")
    else:
        tactic_sources.append("-JIT_CONVOLUTIONS")

    args.append(f"--tacticSources={','.join(tactic_sources)}")

    if use_cuda_graph:
        # enabled by default in TensorRT 11
        pass
    else:
        args.append("--noCudaGraph")
        args.append("--skipInference")

    args.append(f"--builderOptimizationLevel={builder_optimization_level}")

    if max_aux_streams is not None:
        args.append(f"--maxAuxStreams={max_aux_streams}")

    if max_tactics is not None:
        args.append(f"--maxTactics={max_tactics}")

    if tiling_optimization_level != 0:
        args.append(f"--tilingOptimizationLevel={tiling_optimization_level}")
        args.append(f"--l2LimitForTiling={l2_limit_for_tiling}")

    args.extend(custom_args)

    if log:
        env_key = "TRTEXEC_LOG_FILE"
        prev_env_value = os.environ.get(env_key)

        if prev_env_value is not None and len(prev_env_value) > 0:
            # env_key has been set, no extra action
            env = {env_key: prev_env_value, "CUDA_MODULE_LOADING": "LAZY"}
            env.update(**custom_env)
            subprocess.run(args, env=env, check=True, stdout=sys.stderr)
        else:
            time_str = time.strftime('%y%m%d_%H%M%S', time.localtime())

            log_filename = os.path.join(
                tempfile.gettempdir(),
                f"trtexec_{time_str}.log"
            )

            env = {env_key: log_filename, "CUDA_MODULE_LOADING": "LAZY"}
            env.update(**custom_env)

            completed_process = subprocess.run(args, env=env, check=False, stdout=sys.stderr)

            if completed_process.returncode == 0:
                try:
                    os.remove(log_filename)
                except FileNotFoundError:
                    pass
            else:
                if os.path.exists(log_filename):
                    raise RuntimeError(f"trtexec execution fails, log has been written to {log_filename}")
                else:
                    raise RuntimeError(f"trtexec execution fails but no log is found")
    else:
        env = {"CUDA_MODULE_LOADING": "LAZY"}
        env.update(**custom_env)
        subprocess.run(args, env=env, check=True, stdout=sys.stderr)

    return engine_path


def tensorrt_rtx(
    network_path: str,
    channels: int,
    device_id: int,
    opt_shapes: typing.Tuple[int, int],
    max_shapes: typing.Tuple[int, int],
    workspace: typing.Optional[int] = None,
    verbose: bool = False,
    use_cuda_graph: bool = False,
    static_shape: bool = True,
    min_shapes: typing.Tuple[int, int] = (0, 0),
    use_edge_mask_convolutions: bool = True,
    input_name: str = "input",
    builder_optimization_level: int = 3,
    max_aux_streams: typing.Optional[int] = None,
    short_path: typing.Optional[bool] = None,
    custom_env: typing.Dict[str, str] = {},
    custom_args: typing.List[str] = [],
    engine_folder: typing.Optional[str] = None,
    max_tactics: typing.Optional[int] = None,
    tiling_optimization_level: int = 0,
    l2_limit_for_tiling: int = -1,
) -> str:

    if isinstance(opt_shapes, int):
        opt_shapes = (opt_shapes, opt_shapes)

    if isinstance(max_shapes, int):
        max_shapes = (max_shapes, max_shapes)

    try:
        device_name = core.trt_rtx.DeviceProperties(device_id)["name"].decode()
        device_name = device_name.replace(' ', '-')
    except AttributeError:
        device_name = f"device{device_id}"

    engine_path = get_engine_path(
        network_path=network_path,
        min_shapes=min_shapes,
        opt_shapes=opt_shapes,
        max_shapes=max_shapes,
        workspace=workspace,
        static_shape=static_shape,
        builder_optimization_level=builder_optimization_level,
        max_aux_streams=max_aux_streams,
        short_path=short_path,
        engine_folder=engine_folder,
        device_name=device_name,
        is_rtx=True,
    )

    if os.access(engine_path, mode=os.R_OK) and os.path.getsize(engine_path) >= 1024:
        return engine_path

    # do not consider alternative path when the engine_folder is given
    if engine_folder is None:
        alter_engine_path = os.path.join(
            tempfile.gettempdir(),
            os.path.splitdrive(engine_path)[1][1:]
        )

        if os.access(alter_engine_path, mode=os.R_OK) and os.path.getsize(alter_engine_path) >= 1024:
            return alter_engine_path

    try:
        # test writability
        with open(engine_path, "w") as f:
            pass
        os.remove(engine_path)
    except PermissionError:
        if engine_folder is None:
            print(f"{engine_path} is not writable", file=sys.stderr)
            engine_path = alter_engine_path
            dirname = os.path.dirname(engine_path)
            if not os.path.exists(dirname):
                os.makedirs(dirname)
            print(f"change engine path to {engine_path}", file=sys.stderr)
        else:
            # do not consider alternative path when the engine_folder is given
            raise PermissionError(f"{engine_path} is not writable")

    args = [
        tensorrt_rtx_path,
        f"--onnx={network_path}",
        f"--timingCacheFile={engine_path}.cache",
        f"--device={device_id}",
        f"--saveEngine={engine_path}",
        "--useGpu",
    ]

    if workspace is not None:
        args.append(f"--memPoolSize=workspace:{workspace}")

    if static_shape:
        args.append(f"--shapes={input_name}:1x{channels}x{opt_shapes[1]}x{opt_shapes[0]}")
    else:
        args.extend([
            f"--minShapes={input_name}:1x{channels}x{min_shapes[1]}x{min_shapes[0]}",
            f"--optShapes={input_name}:1x{channels}x{opt_shapes[1]}x{opt_shapes[0]}",
            f"--maxShapes={input_name}:1x{channels}x{max_shapes[1]}x{max_shapes[0]}",
            "--specializeStrategyDS=eager"
        ])

    if verbose:
        args.append("--verbose")

    tactic_sources = []

    if use_edge_mask_convolutions:
        tactic_sources.append("+EDGE_MASK_CONVOLUTIONS")
    else:
        tactic_sources.append("-EDGE_MASK_CONVOLUTIONS")

    args.append(f"--tacticSources={','.join(tactic_sources)}")

    if use_cuda_graph:
        args.extend((
            "--useCudaGraph",
            "--noDataTransfers"
        ))
    else:
        args.append("--skipInference")

    args.append(f"--builderOptimizationLevel={builder_optimization_level}")

    if max_aux_streams is not None:
        args.append(f"--maxAuxStreams={max_aux_streams}")

    if max_tactics is not None:
        args.append(f"--maxTactics={max_tactics}")

    if tiling_optimization_level != 0:
        args.append(f"--tilingOptimizationLevel={tiling_optimization_level}")
        args.append(f"--l2LimitForTiling={l2_limit_for_tiling}")

    args.extend(custom_args)

    env = {"CUDA_MODULE_LOADING": "LAZY"}
    env.update(**custom_env)
    subprocess.run(args, env=env, check=True, stdout=sys.stderr)

    return engine_path


def calc_size(width: int, tiles: int, overlap: int, multiple: int = 1) -> int:
    return math.ceil((width + 2 * overlap * (tiles - 1)) / (tiles * multiple)) * multiple


def calc_tilesize(
    tiles: typing.Optional[typing.Union[int, typing.Tuple[int, int]]],
    tilesize: typing.Optional[typing.Union[int, typing.Tuple[int, int]]],
    width: int,
    height: int,
    multiple: int,
    overlap_w: int,
    overlap_h: int
) -> typing.Tuple[typing.Tuple[int, int], typing.Tuple[int, int]]:

    if tilesize is None:
        if tiles is None:
            overlap_w = 0
            overlap_h = 0
            tile_w = width
            tile_h = height
        elif isinstance(tiles, int):
            tile_w = calc_size(width, tiles, overlap_w, multiple)
            tile_h = calc_size(height, tiles, overlap_h, multiple)
        else:
            tile_w = calc_size(width, tiles[0], overlap_w, multiple)
            tile_h = calc_size(height, tiles[1], overlap_h, multiple)
    elif isinstance(tilesize, int):
        tile_w = tilesize
        tile_h = tilesize
    else:
        tile_w, tile_h = tilesize

    return (tile_w, tile_h), (overlap_w, overlap_h)


def init_backend(
    backend: backendT,
    trt_opt_shapes: typing.Tuple[int, int]
) -> backendT:

    if backend is Backend.TRT:  # type: ignore
        backend = Backend.TRT()
    elif backend is Backend.TRT_RTX:  # type: ignore
        backend = Backend.TRT_RTX()
    elif backend is Backend.ORT_DML:  # type: ignore
        backend = Backend.ORT_DML()

    backend = copy.deepcopy(backend)

    if isinstance(backend, (Backend.TRT, Backend.TRT_RTX)):
        if backend.opt_shapes is None:
            backend.opt_shapes = trt_opt_shapes

        if backend.max_shapes is None:
            backend.max_shapes = backend.opt_shapes

    return backend


def _inference(
    clips: typing.List[vs.VideoNode],
    network_path: typing.Union[bytes, str],
    overlap: typing.Tuple[int, int],
    tilesize: typing.Tuple[int, int],
    backend: backendT,
    path_is_serialization: bool = False,
    input_name: str = "input",
    flexible_output_prop: typing.Optional[str] = None,
    batch_size: int = 1
) -> typing.Union[vs.VideoNode, typing.Dict[str, typing.Any]]:

    if not path_is_serialization:
        network_path = typing.cast(str, network_path)
        if not os.path.exists(network_path):
            raise RuntimeError(
                f'"{network_path}" not found, '
                "built-in models can be found at "
                "https://github.com/AmusementClub/vs-mlrt/releases/tag/model-20211209, "
                "https://github.com/AmusementClub/vs-mlrt/releases/tag/model-20220923 and "
                "https://github.com/AmusementClub/vs-mlrt/releases/tag/external-models"
            )

    if path_is_serialization:
        if isinstance(backend, Backend.TRT):
            raise ValueError('"path_is_serialization" must be False for trt backend')
        elif isinstance(backend, Backend.TRT_RTX):
            raise ValueError('"path_is_serialization" must be False for trt_rtx backend')

    if not isinstance(batch_size, int) or batch_size < 1:
        raise ValueError('"batch_size" must be a positve integer')

    if batch_size > 1:
        import numpy as np
        import onnx

        if path_is_serialization:
            model = onnx.load_model_from_string(network_path)
        else:
            model = onnx.load(network_path)

        graph = model.graph
        in_channels = graph.input[0].type.tensor_type.shape.dim[1].dim_value
        graph.input[0].type.tensor_type.shape.dim[1].dim_value *= batch_size
        graph.output[0].type.tensor_type.shape.dim[1].dim_param = "_vsmlrt_output_channels"

        input_name = graph.input[0].name
        output_name = graph.output[0].name
        for node in graph.node:
            for i, name in enumerate(node.input):
                if name == input_name:
                    node.input[i] = "_vsmlrt_input"

            for i, name in enumerate(node.output):
                if name == output_name:
                    node.output[i] = "_vsmlrt_output"

        graph.node.insert(1, onnx.helper.make_node(
            op_type="Constant",
            inputs=[],
            outputs=["_vsmlrt_input_shape"],
            value=onnx.numpy_helper.from_array(np.array([-1, in_channels, 0, 0]))
        ))
        graph.node.insert(2, onnx.helper.make_node(
            op_type="Reshape",
            inputs=[input_name, "_vsmlrt_input_shape"],
            outputs=["_vsmlrt_input"]
        ))

        graph.node.insert(-1, onnx.helper.make_node(
            op_type="Constant",
            inputs=[],
            outputs=["_vsmlrt_output_shape"],
            value=onnx.numpy_helper.from_array(np.array([1, -1, 0, 0]))
        ))
        graph.node.insert(-1, onnx.helper.make_node(
            op_type="Reshape",
            inputs=["_vsmlrt_output", "_vsmlrt_output_shape"],
            outputs=[output_name]
        ))

        if backend.supports_onnx_serialization:
            network_path = model.SerializeToString()
        else:
            network_path = f"{network_path}_batch{batch_size}.onnx"
            onnx.save(model, network_path)

        path_is_serialization = backend.supports_onnx_serialization

        pad = (batch_size - clips[0].num_frames % batch_size) % batch_size
        if pad:
            clips = [clip.std.DuplicateFrames([clip.num_frames - 1] * pad) for clip in clips]

        clips = [
            clip[i::batch_size]
            for i in range(batch_size)
            for clip in clips
        ]

        flexible_output_prop_orig = flexible_output_prop

        if flexible_output_prop is None:
            flexible_output_prop = "vsmlrt_flexible_batch"

    kwargs = dict(overlap=overlap, tilesize=tilesize)
    if flexible_output_prop is not None:
        kwargs["flexible_output_prop"] = flexible_output_prop

    if isinstance(backend, Backend.ORT_DML):
        version_list = core.ort.Version().get("onnxruntime_version", b"0.0.0").split(b'.')
        if len(version_list) != 3:
            version = (0, 0, 0)
        else:
            version = tuple(map(int, version_list))

        if version >= (1, 18, 0):
            kwargs["output_format"] = backend.output_format

        ret = core.ort.Model(
            clips, network_path,
            provider="DML", builtin=False,
            device_id=backend.device_id,
            num_streams=backend.num_streams,
            verbosity=backend.verbosity,
            fp16=False,
            path_is_serialization=path_is_serialization,
            **kwargs
        )
    elif isinstance(backend, Backend.TRT):
        network_path = typing.cast(str, network_path)

        channels = sum(clip.format.num_planes for clip in clips)

        opt_shapes = backend.opt_shapes if backend.opt_shapes is not None else tilesize
        max_shapes = backend.max_shapes if backend.max_shapes is not None else tilesize

        engine_path = trtexec(
            network_path,
            channels=channels,
            opt_shapes=opt_shapes,
            max_shapes=max_shapes,
            device_id=backend.device_id,
            workspace=backend.workspace,
            verbose=backend.verbose,
            use_cuda_graph=backend.use_cuda_graph,
            static_shape=backend.static_shape,
            log=backend.log,
            use_edge_mask_convolutions=backend.use_edge_mask_convolutions,
            use_jit_convolutions=backend.use_jit_convolutions,
            input_name=input_name,
            min_shapes=backend.min_shapes,
            builder_optimization_level=backend.builder_optimization_level,
            max_aux_streams=backend.max_aux_streams,
            short_path=backend.short_path,
            custom_env=backend.custom_env,
            custom_args=backend.custom_args,
            engine_folder=backend.engine_folder,
            max_tactics=backend.max_tactics,
            tiling_optimization_level=backend.tiling_optimization_level,
            l2_limit_for_tiling=backend.l2_limit_for_tiling,
        )
        ret = core.trt.Model(
            clips, engine_path,
            device_id=backend.device_id,
            use_cuda_graph=backend.use_cuda_graph,
            num_streams=backend.num_streams,
            verbosity=4 if backend.verbose else 2,
            **kwargs
        )
    elif isinstance(backend, Backend.TRT_RTX):
        network_path = typing.cast(str, network_path)

        channels = sum(clip.format.num_planes for clip in clips)

        opt_shapes = backend.opt_shapes if backend.opt_shapes is not None else tilesize
        max_shapes = backend.max_shapes if backend.max_shapes is not None else tilesize

        engine_path = tensorrt_rtx(
            network_path,
            channels=channels,
            device_id=backend.device_id,
            opt_shapes=opt_shapes,
            max_shapes=max_shapes,
            workspace=backend.workspace,
            verbose=backend.verbose,
            use_cuda_graph=backend.use_cuda_graph,
            static_shape=backend.static_shape,
            min_shapes=backend.min_shapes,
            use_edge_mask_convolutions=backend.use_edge_mask_convolutions,
            input_name=input_name,
            builder_optimization_level=backend.builder_optimization_level,
            max_aux_streams=backend.max_aux_streams,
            short_path=backend.short_path,
            custom_env=backend.custom_env,
            custom_args=backend.custom_args,
            engine_folder=backend.engine_folder,
            max_tactics=backend.max_tactics,
            tiling_optimization_level=backend.tiling_optimization_level,
            l2_limit_for_tiling=backend.l2_limit_for_tiling,
        )
        ret = core.trt_rtx.Model(
            clips, engine_path,
            device_id=backend.device_id,
            use_cuda_graph=backend.use_cuda_graph,
            num_streams=backend.num_streams,
            verbosity=4 if backend.verbose else 2,
            **kwargs
        )
    else:
        raise TypeError(f'unknown backend {backend}')

    if batch_size > 1:
        clip = ret["clip"]
        num_planes = ret["num_planes"]
        clips = [
            clip.std.PropToClip(prop=f"{flexible_output_prop}{i}")
            for i in range(num_planes)
        ]

        if flexible_output_prop_orig is None:
            if num_planes == batch_size * 3:
                clips = [
                    core.std.ShufflePlanes(clips[i:i+3], [0] * 3, vs.RGB)
                    for i in range(0, num_planes, 3)
                ]
            elif num_planes != batch_size:
                raise ValueError("number of output channels must be 1 or 3")

            ret = core.std.Interleave(clips)
            if pad:
                ret = ret[:-pad]
        else:
            clips = [core.std.Interleave(clips[i::batch_size]) for i in range(num_planes // batch_size)]
            if pad:
                clips = [clip[:-pad] for clip in clips]

            clip = clip.std.BlankClip(keep=True)
            for i in range(len(clips)):
                clip = clip.std.ClipToProp(clips[i], f"{flexible_output_prop_orig}{i}")

            ret = dict(clip=clip, num_planes=len(clips))

    return ret


def inference_with_fallback(
    clips: typing.List[vs.VideoNode],
    network_path: typing.Union[bytes, str],
    overlap: typing.Tuple[int, int],
    tilesize: typing.Tuple[int, int],
    backend: backendT,
    path_is_serialization: bool = False,
    input_name: str = "input",
    batch_size: int = 1 # experimental
) -> vs.VideoNode:

    try:
        ret = _inference(
            clips=clips, network_path=network_path,
            overlap=overlap, tilesize=tilesize,
            backend=backend,
            path_is_serialization=path_is_serialization,
            input_name=input_name,
            batch_size=batch_size
        )
    except Exception as e:
        if fallback_backend is not None:
            import logging
            logger = logging.getLogger("vsmlrt")
            logger.warning(f'"{backend}" fails, trying fallback backend "{fallback_backend}"')

            ret = _inference(
                clips=clips, network_path=network_path,
                overlap=overlap, tilesize=tilesize,
                backend=fallback_backend,
                path_is_serialization=path_is_serialization,
                input_name=input_name,
                batch_size=batch_size
            )
        else:
            raise e

    return typing.cast(vs.VideoNode, ret)


def inference(
    clips: typing.Union[vs.VideoNode, typing.List[vs.VideoNode]],
    network_path: str,
    overlap: typing.Tuple[int, int] = (0, 0),
    tilesize: typing.Optional[typing.Tuple[int, int]] = None,
    backend: backendT = Backend.ORT_DML(),
    input_name: typing.Optional[str] = "input",
    batch_size: int = 1, # experimental
    path_is_serialization: bool = False,
) -> vs.VideoNode:

    if isinstance(clips, vs.VideoNode):
        clips = [clips]

    if tilesize is None:
        tilesize = (clips[0].width, clips[0].height)

    backend = init_backend(backend=backend, trt_opt_shapes=tilesize)

    if input_name is None:
        input_name = get_input_name(network_path)

    return inference_with_fallback(
        clips=clips,
        network_path=network_path,
        overlap=overlap,
        tilesize=tilesize,
        backend=backend,
        path_is_serialization=path_is_serialization,
        input_name=input_name,
        batch_size=batch_size
    )


def flexible_inference_with_fallback(
    clips: typing.List[vs.VideoNode],
    network_path: typing.Union[bytes, str],
    overlap: typing.Tuple[int, int],
    tilesize: typing.Tuple[int, int],
    backend: backendT,
    path_is_serialization: bool = False,
    input_name: str = "input",
    flexible_output_prop: str = "vsmlrt_flexible",
    batch_size: int = 1 # experimental
) -> typing.List[vs.VideoNode]:

    try:
        ret = _inference(
            clips=clips, network_path=network_path,
            overlap=overlap, tilesize=tilesize,
            backend=backend,
            path_is_serialization=path_is_serialization,
            input_name=input_name,
            flexible_output_prop=flexible_output_prop,
            batch_size=batch_size
        )
    except Exception as e:
        if fallback_backend is not None:
            import logging
            logger = logging.getLogger("vsmlrt")
            logger.warning(f'"{backend}" fails, trying fallback backend "{fallback_backend}"')

            ret = _inference(
                clips=clips, network_path=network_path,
                overlap=overlap, tilesize=tilesize,
                backend=fallback_backend,
                path_is_serialization=path_is_serialization,
                input_name=input_name,
                flexible_output_prop=flexible_output_prop,
                batch_size=batch_size
            )
        else:
            raise e

    ret = typing.cast(typing.Dict[str, typing.Any], ret)
    clip = ret["clip"]
    num_planes = ret["num_planes"]

    planes = [
        clip.std.PropToClip(prop=f"{flexible_output_prop}{i}")
        for i in range(num_planes)
    ]

    return planes


def flexible_inference(
    clips: typing.Union[vs.VideoNode, typing.List[vs.VideoNode]],
    network_path: str,
    overlap: typing.Tuple[int, int] = (0, 0),
    tilesize: typing.Optional[typing.Tuple[int, int]] = None,
    backend: backendT = Backend.ORT_DML(),
    input_name: typing.Optional[str] = "input",
    flexible_output_prop: str = "vsmlrt_flexible",
    batch_size: int = 1 # experimental
) -> typing.List[vs.VideoNode]:

    if isinstance(clips, vs.VideoNode):
        clips = [clips]

    if tilesize is None:
        tilesize = (clips[0].width, clips[0].height)

    backend = init_backend(backend=backend, trt_opt_shapes=tilesize)

    if input_name is None:
        input_name = get_input_name(network_path)

    return flexible_inference_with_fallback(
        clips=clips,
        network_path=network_path,
        overlap=overlap,
        tilesize=tilesize,
        backend=backend,
        path_is_serialization=False,
        input_name=input_name,
        flexible_output_prop=flexible_output_prop,
        batch_size=batch_size
    )


def get_input_name(network_path: str) -> str:
    import onnx
    model = onnx.load(network_path)
    return model.graph.input[0].name


def bits_as(clip: vs.VideoNode, target: vs.VideoNode) -> vs.VideoNode:
    if clip.format.bits_per_sample == target.format.bits_per_sample:
        return clip
    else:
        is_api4 = hasattr(vs, "__api_version__") and vs.__api_version__.api_major == 4
        query_video_format = core.query_video_format if is_api4 else core.register_format
        format = query_video_format(
            color_family=clip.format.color_family,
            sample_type=clip.format.sample_type,
            bits_per_sample=target.format.bits_per_sample,
            subsampling_w=clip.format.subsampling_w,
            subsampling_h=clip.format.subsampling_h
        )
        return clip.resize.Point(format=format)


class BackendV2:
    """ simplified backend interfaces with keyword-only arguments """

    @staticmethod
    def TRT(*,
        num_streams: int = 1,
        workspace: typing.Optional[int] = None,
        static_shape: bool = True,
        min_shapes: typing.Tuple[int, int] = (0, 0),
        opt_shapes: typing.Optional[typing.Tuple[int, int]] = None,
        max_shapes: typing.Optional[typing.Tuple[int, int]] = None,
        device_id: int = 0,
        **kwargs
    ) -> Backend.TRT:

        return Backend.TRT(
            num_streams=num_streams,
            workspace=workspace,
            static_shape=static_shape,
            min_shapes=min_shapes, opt_shapes=opt_shapes, max_shapes=max_shapes,
            device_id=device_id,
            **kwargs
        )

    @staticmethod
    def TRT_RTX(*,
        num_streams: int = 1,
        workspace: typing.Optional[int] = None,
        use_cuda_graph: bool = False,
        static_shape: bool = True,
        min_shapes: typing.Tuple[int, int] = (0, 0),
        opt_shapes: typing.Optional[typing.Tuple[int, int]] = None,
        max_shapes: typing.Optional[typing.Tuple[int, int]] = None,
        device_id: int = 0,
        **kwargs
    ) -> Backend.TRT_RTX:

        return Backend.TRT_RTX(
            num_streams=num_streams,
            workspace=workspace, use_cuda_graph=use_cuda_graph,
            static_shape=static_shape,
            min_shapes=min_shapes, opt_shapes=opt_shapes, max_shapes=max_shapes,
            device_id=device_id,
            **kwargs
        )

    @staticmethod
    def ORT_DML(*,
        device_id: int = 0,
        num_streams: int = 1,
        **kwargs
    ) -> Backend.ORT_DML:

        return Backend.ORT_DML(
            device_id=device_id,
            num_streams=num_streams,
            **kwargs
        )


def fmtc_resample(clip: vs.VideoNode, **kwargs) -> vs.VideoNode:
    clip_org = clip

    if clip.format.sample_type == vs.FLOAT and clip.format.bits_per_sample != 32:
        format = clip.format.replace(core=core, bits_per_sample=32)
        clip = core.resize.Point(clip, format=format.id)

    clip = core.fmtc.resample(clip, **kwargs)

    if clip.format.bits_per_sample != clip_org.format.bits_per_sample:
        clip = core.resize.Point(clip, format=clip_org.format.id)

    return clip
