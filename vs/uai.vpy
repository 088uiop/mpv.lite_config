import k7sfunc

## 整数，预降低处理源分辨率
wpre = 1920
hpre = 1080

## <True|False> 使用TRT(True)还是DML(False)
trt = True

## <True|False> 使用TensorRT-RTX
rtx = False

## <True|False> 使用静态引擎(True)还是动态引擎(False)
static = True

## 指定使用的模型，文件放置位为 .../mpv/vs-plugins/models/uai/
model = "HFA2kCompact_x2.onnx"

## 限制最高输入分辨率
wlim = 1920
hlim = 1080

## 限制最高输入帧率
fmax = 60

## 限制最高输出分辨率
wmax = 3840
hmax = 2160

## 使用的显卡序号，0为排序一号
gpu = 0

## <True|False> 锁定像素格式为yuv420p8
lkfmt = False

clip = video_in
fin = container_fps
clip = k7sfunc.FPS_LIMIT(clip, fin, fmax)
clip = k7sfunc.FMT_LIMIT(clip, wlim, hlim)
clip = k7sfunc.FMT_DSCALE(clip, wpre, hpre, lkfmt)
clip = k7sfunc.UAI(clip, trt, rtx, static, model, gpu)
clip = k7sfunc.FMT_DSCALE(clip, wmax, hmax, lkfmt)
clip.set_output()