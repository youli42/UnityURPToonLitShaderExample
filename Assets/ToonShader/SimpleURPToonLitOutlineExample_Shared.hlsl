// 更多信息 -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

// #pragma once 是几乎所有 .hlsl 都推荐的安全写法（需 Unity2020 及以上）：
// 这样使用者在任何位置重复 include 本文件，都不会产生多重 include 冲突
#pragma once

// SRP/URP 包里已经没有 "UnityCG.cginc" 了，所以：
// 做 Universal Pipeline 着色，只需 include 下面两个文件，所需内容全在里面。
// Core.hlsl：包含 SRP shader 库、所有与材质无关的常量缓冲（perObject/perCamera/perFrame），
// 另外还包含矩阵/空间转换函数与雾。
// Lighting.hlsl：包含光照函数与数据，用来抽象光照常量。应使用 GetMainLight / GetLight
// 初始化 Light 结构体。它还包含 GI、Light BRDF 函数，也包含阴影。

// 所有 Universal Render Pipeline shader 的必需项。
// 它包含 Unity 内置 shader 变量（光照变量除外）
// (https://docs.unity3d.com/Manual/SL-UnityShaderVariables.html
// 也包含大量工具函数。
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

// 做受光（lit）shader 才需要 include 它：包含光照 shader 变量、
// 光照与阴影函数
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

// 材质相关的 shader 变量不在 SRP 或 URP 的 shader 库里定义。
// 即 _BaseColor、_BaseMap、_BaseMap_ST 以及 shader Properties 里的全部变量，
// 都必须由 shader 自己声明。只要把它们全放进名为 UnityPerMaterial 的 CBUFFER，
// SRP 就能跨帧缓存材质属性，显著降低每个 drawcall 的开销
// —— 这是 SRP 合批（SRP batching）成立的前提。
// URP 的 LitInput.hlsl 虽然也含上述属性的 CBUFFER，
// 但它是 URP Lit shader 专用的，不属于 ShaderLibrary。
// 所以我们不引用 LitInput.hlsl，
// 全部自己实现。
//#include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"

// 引入若干工具 .hlsl 来帮我们
#include "NiloOutlineUtil.hlsl"
#include "NiloZOffset.hlsl"
#include "NiloInvLerpRemap.hlsl"

// 命名注意：
// 后缀 OS = 物体空间 object space (如 positionOS = position object space)
// 后缀 WS = 世界空间 world space   (如 positionWS = position world space)
// 后缀 VS = 视图空间 view space    (如 positionVS = position view space)
// 后缀 CS = 裁剪空间 clip space    (如 positionCS = position clip space)

// 所有 pass 共用这个 Attributes 结构体（定义 Unity 应用侧传给顶点着色器的数据）
struct Attributes
{
    float3 positionOS   : POSITION;
    half3 normalOS      : NORMAL;
    half4 tangentOS     : TANGENT;
    float2 uv           : TEXCOORD0;

    // 为支持 GPU instancing 与单遍立体渲染（Single Pass Stereo, VR），加入以下内容
    UNITY_VERTEX_INPUT_INSTANCE_ID      // 非 PSSL 平台下等价于 -> uint instanceID : SV_InstanceID;
};

// 所有 pass 共用这个 Varyings 结构体（定义顶点着色器传给片元着色器的数据）
struct Varyings
{
    float2 uv                       : TEXCOORD0;
    float4 positionWSAndFogFactor   : TEXCOORD1; // xyz: positionWS，w: 顶点雾因子
    half3 normalWS                  : TEXCOORD2;
    float4 positionCS               : SV_POSITION;

    // 为支持 GPU instancing 与单遍立体渲染（Single Pass Stereo, VR），加入以下内容
    UNITY_VERTEX_INPUT_INSTANCE_ID  // 非 PSSL 平台下等价于 -> uint instanceID : SV_InstanceID;
    UNITY_VERTEX_OUTPUT_STEREO      // 非 OpenGL、非 PSSL 平台下等价于 -> uint stereoTargetEyeIndexAsRTArrayIdx : SV_RenderTargetArrayIndex;（开启 UNITY_STEREO_INSTANCING_ENABLED 时）
};

///////////////////////////////////////////////////////////////////////////////////////
// CBUFFER 与 Uniform 
// 所有 pass 的全部 uniform 都必须放进这一个 UnityPerMaterial CBUFFER！否则无法 SRP 合批！
///////////////////////////////////////////////////////////////////////////////////////

// 所有 sampler2D 都不需要放进 CBUFFER 
sampler2D _BaseMap; 
sampler2D _EmissionMap;
sampler2D _OcclusionMap;
sampler2D _OutlineZOffsetMaskTex;

// 要把你的所有 uniform（通常是 .shader 文件 Properties{} 里的东西）放进这个 CBUFFER，才兼容 SRP Batcher
// 参见 -> https://blogs.unity3d.com/2019-02-28/srp-batcher-speed-up-your-rendering/
CBUFFER_START(UnityPerMaterial)
    
    // 高层设置：_IsFace 标记脸/眼/嘴，使其与身体共用本 shader（后面用它微调 ZOffset 与阴影采样偏移）
    float   _IsFace;

    // 基础色
    float4  _BaseMap_ST;
    half4   _BaseColor;

    // alpha（透明裁剪）
    half    _Cutoff;

    // 自发光
    float   _UseEmission;
    half3   _EmissionColor;
    half    _EmissionMulByBaseColor;
    half3   _EmissionMapChannelMask;

    // 遮蔽
    float   _UseOcclusion;
    half    _OcclusionStrength;
    half4   _OcclusionMapChannelMask;
    half    _OcclusionRemapStart;
    half    _OcclusionRemapEnd;

    // 光照
    half3   _IndirectLightMinColor;
    half    _CelShadeMidPoint;
    half    _CelShadeSoftness;

    // 阴影贴图
    half    _ReceiveShadowMappingAmount;
    float   _ReceiveShadowMappingPosOffset;
    half3   _ShadowMapColor;

    // 描边
    float   _OutlineWidth;
    half3   _OutlineColor;
    float   _OutlineZOffset;
    float   _OutlineZOffsetMaskRemapStart;
    float   _OutlineZOffsetMaskRemapEnd;

CBUFFER_END

//一个特殊的 applyShadowBiasFixToHClipPos() 专用 uniform，它不是逐材质 uniform，
//所以写在我们 UnityPerMaterial CBUFFER 外面没关系
float3 _LightDirection;

struct ToonSurfaceData
{
    half3   albedo;
    half    alpha;
    half3   emission;
    half    occlusion;
};
struct ToonLightingData
{
    half3   normalWS;
    float3  positionWS;
    half3   viewDirectionWS;
    float4  shadowCoord;
};

///////////////////////////////////////////////////////////////////////////////////////
// 顶点着色器共用函数
///////////////////////////////////////////////////////////////////////////////////////

float3 TransformPositionWSToOutlinePositionWS(float3 positionWS, float positionVS_Z, float3 normalWS)
{
    //你可以换成自己的方法！这里为教程写了一个简单的世界空间做法，并不是最优！
    float outlineExpandAmount = _OutlineWidth * GetOutlineCameraFovAndDistanceFixMultiplier(positionVS_Z);

    #if defined(UNITY_STEREO_INSTANCING_ENABLED) || defined(UNITY_STEREO_MULTIVIEW_ENABLED) || defined(UNITY_STEREO_DOUBLE_WIDE_ENABLED)
    outlineExpandAmount *= 0.5;
    #endif
    
    return positionWS + normalWS * outlineExpandAmount; 
}

// 未定义 "ToonShaderIsOutline" = 只做常规 MVP 变换
// 定义 "ToonShaderIsOutline"   = 常规 MVP 变换 + 沿法线方向把顶点向外推一点（法线外扩描边）
Varyings VertexShaderWork(Attributes input)
{
    Varyings output;

    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    // 处理完无效/被丢弃的顶点后，尽快做这一段。
    // 为支持 GPU instancing 与单遍立体渲染（VR），加入以下内容
    /////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
    UNITY_SETUP_INSTANCE_ID(input);                 // 非 OpenGL、非 PSSL 平台下会展开成 -> UnitySetupInstanceID(input.instanceID);
    UNITY_TRANSFER_INSTANCE_ID(input, output);      // 非 OpenGL、非 PSSL 平台下会展开成 -> output.instanceID = input.instanceID;
    UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);  // 非 OpenGL、非 PSSL 平台下会展开成 -> output.stereoTargetEyeIndexAsRTArrayIdx = unity_StereoEyeIndex;
    
    // VertexPositionInputs 内含多个空间的位置（世界、视图、齐次裁剪空间、NDC）
    // Unity 编译器会剔除所有未引用的分量（比如你不用视图空间）
    // 所以用这个结构体更灵活，且不增加开销
    VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS);

    // 与 VertexPositionInputs 类似，VertexNormalInputs 内含世界空间的法线、切线、副切线，
    // 未使用同样会被剔除。
    VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);

    float3 positionWS = vertexInput.positionWS;

#ifdef ToonShaderIsOutline
    positionWS = TransformPositionWSToOutlinePositionWS(vertexInput.positionWS, vertexInput.positionVS.z, vertexNormalInput.normalWS);
#endif

    // 逐顶点计算雾因子。
    float fogFactor = ComputeFogFactor(vertexInput.positionCS.z);

    // TRANSFORM_TEX 与旧 shader 库用法相同。
    output.uv = TRANSFORM_TEX(input.uv,_BaseMap);

    // 把 positionWS(xyz) 与雾因子(w) 打包进一个 vector4
    output.positionWSAndFogFactor = float4(positionWS, fogFactor);
    output.normalWS = vertexNormalInput.normalWS; //GetVertexNormalInputs(...) 已经归一化过了

    output.positionCS = TransformWorldToHClip(positionWS);

#ifdef ToonShaderIsOutline
    // [读取 ZOffset 遮罩贴图]
    // 顶点着色器里不能用 tex2D()，因为光栅化之前 ddx 与 ddy 未知，
    // 所以改用 tex2Dlod() 并显式指定 mip 层级 0（层级 0 写进参数 uv 的第 4 个分量）
    float outlineZOffsetMaskTexExplictMipLevel = 0;
    float outlineZOffsetMask = tex2Dlod(_OutlineZOffsetMaskTex, float4(input.uv,0,outlineZOffsetMaskTexExplictMipLevel)).r; //假定它是黑白贴图

    // [重映射 ZOffset 贴图采样值]
    // 先把采样值取反，使默认黑色区域 = 施加 ZOffset，因为描边遮罩贴图惯例是黑色 = 隐藏描边
    outlineZOffsetMask = 1-outlineZOffsetMask;
    outlineZOffsetMask = invLerpClamp(_OutlineZOffsetMaskRemapStart,_OutlineZOffsetMaskRemapEnd,outlineZOffsetMask);// 允许使用者自行取反或重映射

    // [施加 ZOffset，用重映射后的值作 ZOffset 遮罩]
    output.positionCS = NiloGetNewClipPosWithZOffset(output.positionCS, _OutlineZOffset * outlineZOffsetMask + 0.03 * _IsFace);
#endif

    // ShadowCaster pass 必须特殊处理 positionCS，否则会出现阴影瑕疵
    //--------------------------------------------------------------------------------------
#ifdef ToonShaderApplyShadowBiasFix
    // 参考 URP/Shaders/ShadowCasterPass.hlsl 里的 GetShadowPositionHClip()
    // https://github.com/Unity-Technologies/Graphics/blob/master/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl
    float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, output.normalWS, _LightDirection));

    #if UNITY_REVERSED_Z
    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #else
    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
    #endif
    output.positionCS = positionCS;
#endif
    //--------------------------------------------------------------------------------------    

    return output;
}

///////////////////////////////////////////////////////////////////////////////////////
// 片元着色器共用函数（第 1 步：为光照计算准备数据结构体）
///////////////////////////////////////////////////////////////////////////////////////
half4 GetFinalBaseColor(Varyings input)
{
    return tex2D(_BaseMap, input.uv) * _BaseColor;
}
half3 GetFinalEmissionColor(Varyings input)
{
    half3 result = 0;
    if(_UseEmission)
    {
        result = tex2D(_EmissionMap, input.uv).rgb * _EmissionMapChannelMask * _EmissionColor.rgb;
    }

    return result;
}
half GetFinalOcculsion(Varyings input)
{
    half result = 1;
    if(_UseOcclusion)
    {
        half4 texValue = tex2D(_OcclusionMap, input.uv);
        half occlusionValue = dot(texValue, _OcclusionMapChannelMask);
        occlusionValue = lerp(1, occlusionValue, _OcclusionStrength);
        occlusionValue = invLerpClamp(_OcclusionRemapStart, _OcclusionRemapEnd, occlusionValue);
        result = occlusionValue;
    }

    return result;
}
void DoClipTestToTargetAlphaValue(half alpha) 
{
#if _UseAlphaClipping
    clip(alpha - _Cutoff);
#endif
}
ToonSurfaceData InitializeSurfaceData(Varyings input)
{
    ToonSurfaceData output;

    // albedo 与 alpha
    float4 baseColorFinal = GetFinalBaseColor(input);
    output.albedo = baseColorFinal.rgb;
    output.alpha = baseColorFinal.a;
    DoClipTestToTargetAlphaValue(output.alpha);// 可行就尽早丢弃

    // 自发光
    output.emission = GetFinalEmissionColor(input);

    // 遮蔽
    output.occlusion = GetFinalOcculsion(input);

    return output;
}
ToonLightingData InitializeLightingData(Varyings input)
{
    ToonLightingData lightingData;
    lightingData.positionWS = input.positionWSAndFogFactor.xyz;
    lightingData.viewDirectionWS = SafeNormalize(GetCameraPositionWS() - lightingData.positionWS);  
    lightingData.normalWS = normalize(input.normalWS); //插值后的法线不是单位向量，必须归一化

    return lightingData;
}

///////////////////////////////////////////////////////////////////////////////////////
// 片元着色器共用函数（第 2 步：计算光照与最终颜色）
///////////////////////////////////////////////////////////////////////////////////////

// 全部光照方程都写在这个 .hlsl 里，
// 只改这个 .hlsl 就能控制大部分视觉效果。
#include "SimpleURPToonLitOutlineExample_LightingEquation.hlsl"

// 本函数不含任何光照逻辑，只负责在各光照结果之间传递数据
// 它干的活是"给阴影贴图深度测试的 positionWS 做偏移"
half3 ShadeAllLights(ToonSurfaceData surfaceData, ToonLightingData lightingData)
{
    // 间接光（indirect light）
    half3 indirectResult = ShadeGI(surfaceData, lightingData);

    //////////////////////////////////////////////////////////////////////////////////
    // Light 结构体由 URP 提供，用来抽象光照 shader 变量，
    // 它包含光源的：
    // - direction（方向）
    // - color（颜色）
    // - distanceAttenuation （距离衰减）
    // - shadowAttenuation（阴影衰减）
    //
    // URP 会按光源与平台采用不同的着色方式（着色置换 shader permutation）。
    // 永远不要在自己的 shader 里直接引用光照 shader 变量，改用
    // -GetMainLight()
    // -GetLight()
    // 这两个函数来填充 Light 结构体。
    //////////////////////////////////////////////////////////////////////////////////

    //==============================================================================================
    // 主光是最亮的平行光。
    // 它在光照循环之外单独着色，并有专属变量与着色路径，
    // 因此在只有一盏平行光的情况下可以尽可能快
    // 可选地传入 shadowCoord，传了就会计算 shadowAttenuation。
    Light mainLight = GetMainLight();

    float3 shadowTestPosWS = lightingData.positionWS + mainLight.direction * (_ReceiveShadowMappingPosOffset + _IsFace);
#ifdef _MAIN_LIGHT_SHADOWS
    // 因为这个改动，阴影坐标改到片元着色器里计算
    // https://forum.unity.com/threads/shadow-cascades-weird-since-7-2-0.828453/#post-5516425

    // _ReceiveShadowMappingPosOffset 控制阴影比较采样位置的偏移，
    // 这样通常是为了遮掉脸部这类阴影敏感区域上难看的自身阴影
    float4 shadowCoord = TransformWorldToShadowCoord(shadowTestPosWS);
    mainLight.shadowAttenuation = MainLightRealtimeShadow(shadowCoord);
#endif 

    // 主光
    half3 mainLightResult = ShadeSingleLight(surfaceData, lightingData, mainLight, false);

    //==============================================================================================
    // 所有额外光源（additional light）

    half3 additionalLightSumResult = 0;

#ifdef _ADDITIONAL_LIGHTS
    // 返回影响当前被渲染物体的光源数量。
    // 这些光源在 URP 前向渲染中是按物体逐个剔除的。
    int additionalLightsCount = GetAdditionalLightsCount();
    for (int i = 0; i < additionalLightsCount; ++i)
    {
        // 与 GetMainLight() 类似，但接受 for 循环下标：先算出逐物体（per-object）光源索引，
        // 再据此采样 light buffer 初始化 Light 结构体。
        // 定义了 ADDITIONAL_LIGHT_CALCULATE_SHADOWS 时还会计算阴影。
        int perObjectLightIndex = GetPerObjectLightIndex(i);
        Light light = GetAdditionalPerObjectLight(perObjectLightIndex, lightingData.positionWS); // 光照用原始 positionWS
        light.shadowAttenuation = AdditionalLightRealtimeShadow(perObjectLightIndex, shadowTestPosWS); // 阴影测试用偏移后的 positionWS

        // 额外光源改用另一个函数着色。
        additionalLightSumResult += ShadeSingleLight(surfaceData, lightingData, light, true);
    }
#endif
    //==============================================================================================

    // 自发光
    half3 emissionResult = ShadeEmission(surfaceData, lightingData);

    return CompositeAllLightResults(indirectResult, mainLightResult, additionalLightSumResult, emissionResult, surfaceData, lightingData);
}

half3 ConvertSurfaceColorToOutlineColor(half3 originalSurfaceColor)
{
    return originalSurfaceColor * _OutlineColor;
}
half3 ApplyFog(half3 color, Varyings input)
{
    half fogFactor = input.positionWSAndFogFactor.w;
    // 把像素颜色与 fogColor 混合。也可以选择用 MixFogColor 覆盖 fogColor
    // 为自定义雾色。
    color = MixFog(color, fogFactor);

    return color;  
}

// 只有 .shader 文件会调用这个函数，调用方式是
// #pragma fragment ShadeFinalColor
half4 ShadeFinalColor(Varyings input) : SV_TARGET
{
    // 为支持 GPU instancing 与单遍立体渲染（VR），加入以下内容
    //------------------------------------------------------------------------------------------------------------------------------
    UNITY_SETUP_INSTANCE_ID(input);                     // 非 OpenGL、非 PSSL 平台下该宏会展开成 -> UnitySetupInstanceID(input.instanceID);
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);    // 非 OpenGL、非 PSSL 平台下该宏会展开成 -> unity_StereoEyeIndex = input.stereoTargetEyeIndexAsRTArrayIdx;
    //------------------------------------------------------------------------------------------------------------------------------
 
    //////////////////////////////////////////////////////////////////////////////////////////
    // 先把光照函数需要的所有数据准备好
    //////////////////////////////////////////////////////////////////////////////////////////

    // 填充 ToonSurfaceData（表面数据）结构体：
    ToonSurfaceData surfaceData = InitializeSurfaceData(input);

    // 填充 ToonLightingData 结构体：
    ToonLightingData lightingData = InitializeLightingData(input);
 
    // 应用全部光照计算
    half3 color = ShadeAllLights(surfaceData, lightingData);

#ifdef ToonShaderIsOutline
    color = ConvertSurfaceColorToOutlineColor(color);
#endif

    color = ApplyFog(color, input);

    return half4(color, surfaceData.alpha);
}

/////////////////////////////////////////////////////////////////////////////////////////
// 片元着色器共用函数（仅供 ShadowCaster、DepthOnly、DepthNormalsOnly pass 使用）
/////////////////////////////////////////////////////////////////////////////////////////

// 抄自 ShadowCasterPass.hlsl 并改写
void AlphaClipAndLODTest(Varyings input)
{
    DoClipTestToTargetAlphaValue(GetFinalBaseColor(input).a);

    #ifdef LOD_FADE_CROSSFADE
    LODFadeCrossFade(input.positionCS);
    #endif
}

// 抄自 DepthOnlyPass.hlsl 并改写
half DepthOnlyFragment(Varyings input) : SV_TARGET
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    AlphaClipAndLODTest(input);

    return input.positionCS.z;
}

// 抄自 LitDepthNormalsPass.hlsl 并改写
void DepthNormalsFragment(
    Varyings input
    , out half4 outNormalWS : SV_Target0
#ifdef _WRITE_RENDERING_LAYERS
    , out float4 outRenderingLayers : SV_Target1
#endif
)
{
    UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

    AlphaClipAndLODTest(input);

    #if defined(_GBUFFER_NORMALS_OCT)
        float3 normalWS = normalize(input.normalWS);
        float2 octNormalWS = PackNormalOctQuadEncode(normalWS);           // 取值介于 [-1, +1]，某些平台必须用 fp32
        float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);   // 取值介于 [ 0,  1]
        half3 packedNormalWS = PackFloat2To888(remappedOctNormalWS);      // 取值介于 [ 0,  1]
        outNormalWS = half4(packedNormalWS, 0.0);
    #else
        float2 uv = input.uv;
        #if defined(_PARALLAXMAP)
            #if defined(REQUIRES_TANGENT_SPACE_VIEW_DIR_INTERPOLATOR)
                half3 viewDirTS = input.viewDirTS;
            #else
                half3 viewDirTS = GetViewDirectionTangentSpace(input.tangentWS, input.normalWS, input.viewDirWS);
            #endif
            ApplyPerPixelDisplacement(viewDirTS, uv);
        #endif

        #if defined(_NORMALMAP) || defined(_DETAIL)
            float sgn = input.tangentWS.w;      // 应该只能是 +1 或 -1
            float3 bitangent = sgn * cross(input.normalWS.xyz, input.tangentWS.xyz);
            float3 normalTS = SampleNormal(uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);

            #if defined(_DETAIL)
                half detailMask = SAMPLE_TEXTURE2D(_DetailMask, sampler_DetailMask, uv).a;
                float2 detailUv = uv * _DetailAlbedoMap_ST.xy + _DetailAlbedoMap_ST.zw;
                normalTS = ApplyDetailNormal(detailUv, normalTS, detailMask);
            #endif

            float3 normalWS = TransformTangentToWorld(normalTS, half3x3(input.tangentWS.xyz, bitangent.xyz, input.normalWS.xyz));
        #else
            float3 normalWS = input.normalWS;
        #endif

        outNormalWS = half4(NormalizeNormalPerPixel(normalWS), 0.0);
    #endif

    #ifdef _WRITE_RENDERING_LAYERS
        uint renderingLayers = GetMeshRenderingLayer();
        outRenderingLayers = float4(EncodeMeshRenderingLayer(renderingLayers), 0, 0, 0);
    #endif
}
