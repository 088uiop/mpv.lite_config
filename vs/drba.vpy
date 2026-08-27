import k7sfunc

## 整数，预降低处理源分辨率
wpre = 1920
hpre = 1080

## <ort_dml|trt|trt_rtx> 使用的后端
be = "ort_dml"

## <1|2> 使用的模型
model = 2

## 整数，Fnum/Fden 的值即输出
fnum = 2
fden = 1

## <True|False> 输出帧率(True)还是倍率(False)
abs = False

## 限制最高输入帧率
fmax = 30

## <True|False> 场景切换检测
sc = False

## 使用的显卡序号，0为排序一号
gpu = 0

## <True|False> 锁定像素格式为yuv420p8
lkfmt = False

clip = video_in
fin = container_fps
clip = k7sfunc.FPS_LIMIT(clip, fin, fmax)
clip = k7sfunc.FMT_DSCALE(clip, wpre, hpre, lkfmt)
clip = k7sfunc.DRBA(clip, fin, be, model, abs, fnum, fden, sc, gpu)
clip.set_output()