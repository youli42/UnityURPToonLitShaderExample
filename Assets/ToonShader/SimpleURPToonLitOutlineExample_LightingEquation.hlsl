// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// 本文件是给你随意修改、试验不同光照方程用的
// 想加、想改什么代码都写在这里

// #pragma once 是几乎所有 .hlsl 都建议加的防重复包含保护（需 Unity2020 及以上）：
// 这样任何人、在任何地方包含本文件，都不会产生重复包含冲突
#pragma once

half3 ShadeGI(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // SampleSH(0) 传零方向、只取球谐（SH）的常数项，丢弃全部细节 SH 以隐藏立体感
    // 我们只要环境间接光（indirect light）的平均颜色
    half3 averageSH = SampleSH(0);

    // max(_IndirectLightMinColor,...) 兜底：lightprobe 没烘焙时结果不会全黑
    averageSH = max(_IndirectLightMinColor,averageSH);

    // 遮蔽（occlusion）：间接光最多被压暗 50%，同样是为了防止结果全黑
    half indirectOcclusion = lerp(1, surfaceData.occlusion, 0.5);
    return averageSH * indirectOcclusion;
}

// 全 shader 最核心的部分：光照方程，按需修改，怎么写都行，尽情发挥
// 所有直接光（方向光/点光/聚光灯）都走这个函数
half3 ShadeSingleLight(ToonSurfaceData surfaceData, ToonLightingData lightingData, Light light, bool isAdditionalLight)
{
    half3 N = lightingData.normalWS;
    half3 L = light.direction;

    half NoL = dot(N,L);

    half lightAttenuation = 1;

    // 点光/聚光灯的距离与角度衰减（见 Lighting.hlsl 的 GetAdditionalPerObjectLight(...)）
    // Lighting.hlsl -> https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl
    half distanceAttenuation = min(4,light.distanceAttenuation); //clamp 到 4：点光/聚光灯离顶点太近时防止过曝

    // 基于 N·L（NoL）：
    // smoothstep 一行实现最简赛璐璐（cel shade）明暗分界，随时可整行换成你自己的方法
    half litOrShadowArea = smoothstep(_CelShadeMidPoint-_CelShadeSoftness,_CelShadeMidPoint+_CelShadeSoftness, NoL);

    // 乘遮蔽（occlusion）
    litOrShadowArea *= surfaceData.occlusion;

    // 面部(_IsFace)不走 NoL 赛璐璐（通常很丑），只在 0.5~1 间柔和过渡
    litOrShadowArea = _IsFace? lerp(0.5,1,litOrShadowArea) : litOrShadowArea;

    // 乘阴影贴图（shadow map）的 shadowAttenuation，接收强度由 _ReceiveShadowMappingAmount 控制
    litOrShadowArea *= lerp(1,light.shadowAttenuation,_ReceiveShadowMappingAmount);

    half3 litOrShadowColor = lerp(_ShadowMapColor,1, litOrShadowArea);

    half3 lightAttenuationRGB = litOrShadowColor * distanceAttenuation;

    // saturate() 光源颜色，防过曝
    // 额外光源是叠加计入的，统一乘 0.25 降低强度
    return saturate(light.color) * lightAttenuationRGB * (isAdditionalLight ? 0.25 : 1);
}

half3 ShadeEmission(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    half3 emissionResult = lerp(surfaceData.emission, surfaceData.emission * surfaceData.albedo, _EmissionMulByBaseColor); // 可选：自发光乘 albedo（基础色）
    return emissionResult;
}

half3 CompositeAllLightResults(half3 indirectResult, half3 mainLightResult, half3 additionalLightSumResult, half3 emissionResult, ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // [这里同样随便你写，下面只是一个简单的教学做法]
    // 目标：既压制灯光过曝，
    // 又保留灯光颜色的色相
    half3 rawLightSum = max(indirectResult, mainLightResult + additionalLightSumResult); // 间接光与直接光取较大值(max)，压过曝的同时保住色相
    return surfaceData.albedo * rawLightSum + emissionResult;
}
