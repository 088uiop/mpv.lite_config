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

## <46|4251|426|4262> 使用的模型
model = 46

## 整数，Fnum/Fden 的值即输出
fnum = 2
fden = 1

## <True|False> 输出帧率(True)还是倍率(False)
abs = False

## 限制最高输入帧率
fmax = 30

## <True|False> 场景切换检测
sc = True

## 使用的显卡序号，0为排序一号
gpu = 0

## <True|False> 锁定像素格式为yuv420p8
lkfmt = False

clip = video_in
fin = container_fps
clip = k7sfunc.FPS_LIMIT(clip, fin, fmax)
clip = k7sfunc.FMT_DSCALE(clip, wpre, hpre, lkfmt)
clip = k7sfunc.RIFE(clip, fin, trt, rtx, static, model, abs, fnum, fden, sc, gpu)
clip.set_output()