// https://github.com/ronja-tutorials/ShaderTutorials/blob/master/Assets/047_InverseInterpolationAndRemap/Interpolation.cginc
// 把 float 改成 half 做优化，因为我们通常用它处理颜色数据(half)

#ifndef Include_NiloInvLerpRemap
#define Include_NiloInvLerpRemap

// 类似 smoothstep()，但是线性、不 clamp
half invLerp(half from, half to, half value) 
{
    return (value - from) / (to - from);
}
half invLerpClamp(half from, half to, half value)
{
    return saturate(invLerp(from,to,value));
}
// 完全可控的重映射（remap），但更慢
half remap(half origFrom, half origTo, half targetFrom, half targetTo, half value)
{
    half rel = invLerp(origFrom, origTo, value);
    return lerp(targetFrom, targetTo, rel);
}
#endif
