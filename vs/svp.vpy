import k7sfunc

## 整数，预降低处理源分辨率
wpre = 1920
hpre = 1080

## 整数，Fnum/Fden 的值即输出
fnum = 60000
fden = 1001

## <True|False> 输出帧率(True)还是倍率(False)
abs = True

## 限制最高输入帧率
fmax = 60

## <True|False> 是否启用Optical Flow（nvidia专用）
nvof = False

## 使用的显卡序号，0为排序一号
gpu = 0

## <True|False> 锁定像素格式为yuv420p8
lkfmt = False

clip = video_in
fin = container_fps
clip = k7sfunc.FPS_LIMIT(clip, fin, fmax)
clip = k7sfunc.FMT_DSCALE(clip, wpre, hpre, lkfmt)
clip = k7sfunc.SVP(clip, fin, fnum, fden, abs, nvof, gpu)
clip.set_output()