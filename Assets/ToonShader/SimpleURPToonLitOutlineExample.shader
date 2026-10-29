// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

/*
本 shader 是一个简短的入门示例：演示如何以"最少"的 shader 代码编写第一个 URP 自定义赛璐璐（cel shade）着色器。
可把它当起点增删代码，开发自己的 URP14(Unity2022.3) 及以上自定义 toon lit shader。

通常只改 "SimpleURPToonLitOutlineExample_LightingEquation.hlsl" 这一个文件，就能控制大部分视觉效果。

本 shader 包含 5 个 pass：
0.UniversalForwardOnly  pass（始终渲染到 _CameraColorAttachment* 与 _CameraDepthAttachment*）
1.Outline               pass（同样始终渲染到颜色与深度附件）
2.ShadowCaster          pass（仅用于 URP 阴影投射渲染，输出到 _MainLightShadowmapTexture* 与 _AdditionalLightsShadowmapTexture*；角色不投影时此 pass 完全不执行）
3.DepthOnly             pass（仅用于 URP 的 _CameraDepthTexture 渲染；项目不做离屏深度预通道（depth prepass）时完全不执行）
4.DepthNormalsOnly      pass（仅用于 _CameraDepthTexture + _CameraNormalsTexture 渲染；项目不做离屏深度+法线预通道时完全不执行）

- 此 toon shader 主要用于独特的动态角色，因此删除了所有 lightmap 相关代码以求简洁。
- 合批只依赖 SRP 合批（SRP batching）：这是 URP 中渲染大量使用同一 shader 的独立蒙皮（SkinnedMeshRenderer）角色最实用的合批方式。

多数属性沿用 URP Lit shader 的命名惯例：把 Lit 材质切换到本 shader 时，凡本 shader 定义过的同名属性都会保留。
命名惯例详见 URP 的 Lit.shader。

本 shader 中，部分可开关特性选择"条件移动（a?b:c）"或"静态 uniform 分支 if(_Uniform)"，而非 "shader_feature & multi_compile"，原因：
    - 避免 shader 编译时间过久（2^n）
    - 避免着色置换（shader permutation）过多导致体积与内存暴涨（2^n）：2GB 内存的 iOS 设备 multi_compile 用多了极易崩溃
    - 避免相机首次遇到新变体时的渲染卡顿（profiler 中的 "create GPU program"）
    - 避免 ShaderVariantCollection 关键字组合复杂度上升
    - 避免破坏 SRP 合批：SRP 合批按 shader 变体合批，而非按 shader

    所有现代 GPU（含最新高端移动设备）都能以"几乎"零性能代价处理静态 uniform 分支（前提：寄存器压力不是瓶颈）。
    分支通常有 4 种情形，按代价从低到高排列如下——一般你只需担心 case 4：

    case 1 - 编译期常量的 if():
        // absolutely 0 performance cost for any platform, unity's shader compiler will treat the false side of if() as dead code and remove it completely
        // shader compiler is very good at dead code removal
        #define SHOULD_RUN_FANCY_CODE 0
        if(SHOULD_RUN_FANCY_CODE) {...}

    case 2 - 静态 uniform 分支 if():
        // reasonable low performance cost (except OpenGLES2, OpenGLES2 doesn't have branching and will always run both paths and discard the false path)
        // since OpenGLES2 is not important anymore in 2024, we will use static uniform branching if() when suitable
        CBUFFER_START(UnityPerMaterial)
            float _ShouldRunFancyCode; // usually controlled by a [Toggle] in material inspector, or material.SetFloat(1 or 0) in C#
        CBUFFER_END
        if(_ShouldRunFancyCode) {...}

    case 3 - 波前/波组（wavefront/warp）内无分支发散的动态 if():
        bool shouldRunFancyCode = (some shader calculation); // all pixels inside a wavefront/warp(imagine it is a group of 8x8 pixels) all goes into the same path, then no divergence.
        if(shouldRunFancyCode) {...}

    case 4 - 波前/波组内存在分支发散（divergence）的动态 if():
        // this is the only case that will make GPU really slow! You will want to avoid it as much as possible
        bool shouldRunFancyCode = (some shader calculation); // pixels inside a wavefront/warp(imagine it is a group of 8x8 pixels) goes into different paths, even it is 63 vs 1 within a 8x8 thread group, it is still divergence!
        if(shouldRunFancyCode) {...} 

    想理解 case 1-4 的区别，可参考这些关于 shader 中 if()/分支/发散代价的资料：
    - https://stackoverflow.com/questions/37827216/do-conditional-statements-slow-down-shaders
    - https://stackoverflow.com/questions/5340237/how-much-performance-do-conditionals-and-unused-samplers-textures-add-to-sm2-3-p/5362006#5362006
    - https://twitter.com/bgolus/status/1235351597816795136
    - https://twitter.com/bgolus/status/1235254923819802626?s=20
    - https://www.shadertoy.com/view/wlsGDl?fbclid=IwAR1ByDhQBck8VO0AMPS5XpbtBPSzSN9Mh8clW4itRgDIpy5ROcXW1Iyf86g

    [TLDR]（记住这些即可，移动端同理）：
    - if() 本身不是恶魔：确认 warp 内无发散就放心用，但它在移动端并非免费
    - "a ? b : c" 只是汇编里的条件移动（movc/cmov）：若 b、c 已经算出，不必担心用它
    - 别用 lerp(b,c,step()) 去"优化" if() 或三元：b、c 已算出时，"a ? b : c" 永远更快
    - 分支不算恶魔，但也不免费：被跳过的工作很重时，分支反而能帮 GPU 提速
    - 发散才是恶魔！用 if(condition){...}else{...} 时，务必让"条件"在尽可能多的 8x8 像素组内保持一致

    【开发者说明 (1)】
    着色置换（multi_compile/shader_feature）仍是跳过 shader 计算最快的方式——代码一旦不存在，编译器就能启用更多优化。
    若追求最佳 GPU 性能、且能接受长构建时间与巨大内存，可更多使用 multi_compile/shader_feature，尤其是涉及贴图读取的特性。

    NiloToonURP 的角色 shader：只要置换能跳过任何贴图读取，就优先用置换——
    2015 年以来 GPU 的 ALU（纯计算）性能增长极强（含移动端），但内存带宽（buffer/贴图读取）增长相对很弱。
    (https://community.arm.com/developer/tools-software/graphics/b/blog/posts/moving-mobile-graphics#siggraph2015)

    GPU 等待贴图数据时并不会空闲：它会继续做所有可用的 ALU 工作（延迟隐藏），直到 100% 无事可算；
    且带宽是最大发热源（无主动散热的移动设备更易过热降频）。
    所以应尽量压低带宽占用（ALU 多一点没问题，贴图读得多不行），最简单的办法就是用着色置换删掉贴图读取。

    但若 if/else 两侧都只是纯 ALU 且计算简单，NiloToonURP 会优先用 "a ? b : c"；
    剩下的才用静态 uniform 分支（通常指 if() 内较重的纯 ALU 代码）。

    【开发者说明 (2)】
    若你在做具体游戏项目（而非 NiloToonURP 这类通用工具），应把 4 类数据（occlusion/specular/smoothness/各类 mask...）打包进一张 RGBA 贴图（供 fragment 用），
    再把另外 4 类数据（outlineWidth/ZOffset/face area mask...）打包进另一张 RGBA 贴图（供 vertex 用）——在不改变视觉效果的前提下（忽略贴图压缩）减少贴图读取次数。
    但 NiloToonURP 面向不同个人/团队/公司，是通用工具：让所有用户都能轻松、零负担地把本 shader 套到任何模型上非常重要，
    强迫普通用户专为它把贴图打包成特殊格式也不实际，
    所以决定每张贴图各自独立——哪怕比打包方式慢很多。
    性能上这是个令人遗憾的决定，但易用性上是好决定；
    不需要极致性能的用户反而因此受益——用这个 shader 时灵活度更高。  

    【关于 multi_compile / shader_feature 的 _vertex、_fragment 后缀】
    Unity 2020.3 为 multi_compile 和 shader_feature 加入了 _vertex、_fragment 后缀：
    https://docs.unity3d.com/2020.3/Documentation/Manual/SL-MultipleProgramVariants.html (Using stage-specific keyword directives)

    不用后缀的唯一缺点是编译时间，不影响构建体积/内存占用：
    https://docs.unity3d.com/2020.3/Documentation/Manual/SL-MultipleProgramVariants.html (Stage-specific keyword directives)
    官方原文："Unity identifies and removes duplicates afterwards, so this redundant work does not affect build sizes or runtime performance; 
    however, if you have a lot of stages and/or variants, the time wasted during shader compilation can be significant."

---------------------------------------------------------------------------
移动 GPU 优化资料（多数最佳实践同样适用于 Mali 与 Adreno 两类 GPU）：
https://developer.arm.com/solutions/graphics-and-gaming/arm-mali-gpu-training

【Shader 构建时间与内存】
https://blog.unity.com/engine-platform/2021-lts-improvements-to-shader-build-times-and-memory-usage

【SinglePassInstancing 支持】
https://docs.unity3d.com/2022.2/Documentation/Manual/SinglePassInstancing.html

【预处理条件可影响 #pragma】
预处理条件可以用来控制选用哪些 #pragma：
https://forum.unity.com/threads/new-shader-preprocessor.790328/
https://docs.unity3d.com/Manual/shader-variant-stripping.html
示例代码：
{
    #ifdef SHADER_API_DESKTOP
        #pragma multi_compile _ RED GREEN BLUE WHITE
    #else
       #pragma shader_feature RED GREEN BLUE WHITE
    #endif
}
{
    #if SHADER_API_DESKTOP
        #pragma geometry ForwardPassGeometry
    #endif
}
{
    #if SHADER_API_DESKTOP
        #pragma vertex DesktopVert
    #else
        #pragma vertex MobileVert
    #endif
}
{
    #if SHADER_API_DESKTOP
       #pragma multi_compile SHADOWS_LOW SHADOWS_HIGH
       #pragma multi_compile REFLECTIONS_LOW REFLECTIONS_HIGH
       #pragma multi_compile CAUSTICS_LOW CAUSTICS_HIGH
    #elif SHADER_API_MOBILE
       #pragma multi_compile QUALITY_LOW QUALITY_HIGH
       #pragma shader_feature CAUSTICS // Uses shader_feature, so Unity strips variants that use CAUSTICS if there are no Materials that use the keyword at build time.
    #endif
}
但下面这样是不行的（来自 pragma（shader_feature、multi_compile 和 variations）的关键字不会影响其它 pragma）：
{
    #pragma shader_feature WIREFRAME_MODE_ON
 
    #ifdef WIREFRAME_MODE_ON
        #pragma geometry ForwardPassGeometry
    #endif
}

【用 IDE 编写 .shader 与 .hlsl】
Rider 是写 Unity shader 最好的 IDE，没有比它更好的工具。
若你从未用 Rider 写过 hlsl，强烈推荐免费试用一个月。
https://www.jetbrains.com/rider/

【Rider 中 hlsl 代码显示为 inactive】
你可能会遇到 #if #endif 区间内某些 hlsl 被判为 inactive，导致 Rider 的"自动补全"和"语法高亮"失效，
解决办法：用 Rider 右下角状态栏的 "Unity Shader Context picker" UI 切换分析上下文。

详见这份关于 "状态栏中的 Unity Shader Context picker" 的 Rider 文档：
https://github.com/JetBrains/resharper-unity/wiki/Switching-code-analysis-context-for-hlsl-cginc-files-in-Rider
*/ 
Shader "SimpleURPToonLitExample(With Outline)"
{
    Properties
    {
        [Header(High Level Setting)]
        [ToggleUI]_IsFace("Is Face? (face/eye/mouth)", Float) = 0

        [Header(Base Color)]
        [MainTexture]_BaseMap("Base Map", 2D) = "white" {}
        [HDR][MainColor]_BaseColor("Base Color", Color) = (1,1,1,1)

        [Header(Alpha Clipping)]
        [Toggle(_UseAlphaClipping)]_UseAlphaClipping("Enable?", Float) = 0
        _Cutoff("    Cutoff", Range(0.0, 1.0)) = 0.5

        [Header(Emission)]
        [Toggle]_UseEmission("Enable?", Float) = 0
        [HDR] _EmissionColor("    Color", Color) = (0,0,0)
        _EmissionMulByBaseColor("    Mul Base Color", Range(0,1)) = 0
        [NoScaleOffset]_EmissionMap("    Emission Map", 2D) = "white" {}
        _EmissionMapChannelMask("        ChannelMask", Vector) = (1,1,1,0)

        [Header(Occlusion)]
        [Toggle]_UseOcclusion("Enable?", Float) = 0
        _OcclusionStrength("    Strength", Range(0.0, 1.0)) = 1.0
        [NoScaleOffset]_OcclusionMap("    OcclusionMap", 2D) = "white" {}
        _OcclusionMapChannelMask("        ChannelMask", Vector) = (1,0,0,0)
        _OcclusionRemapStart("        RemapStart", Range(0,1)) = 0
        _OcclusionRemapEnd("        RemapEnd", Range(0,1)) = 1

        [Header(Indirect Light)]
        _IndirectLightMinColor("Min Color", Color) = (0.1,0.1,0.1,1) // 可防止 light probe 未烘焙时出现全黑
        _IndirectLightMultiplier("Multiplier", Range(0,1)) = 1
        
        [Header(Direct Light)]
        _DirectLightMultiplier("Brightness", Range(0,1)) = 1
        _CelShadeMidPoint("MidPoint", Range(-1,1)) = -0.5
        _CelShadeSoftness("Softness", Range(0,1)) = 0.05
        _MainLightIgnoreCelShade("Remove Shadow", Range(0,1)) = 0
        
        [Header(Additional Light)]
        _AdditionalLightIgnoreCelShade("Remove Shadow", Range(0,1)) = 0.9

        [Header(Shadow Mapping)]
        _ReceiveShadowMappingAmount("Strength", Range(0,1)) = 0.65
        _ShadowMapColor("    Shadow Color", Color) = (1,0.825,0.78)
        _ReceiveShadowMappingPosOffset("    Depth Bias", Float) = 0

        [Header(Outline)]
        _OutlineWidth("Width", Range(0,4)) = 1
        _OutlineColor("Color", Color) = (0.5,0.5,0.5,1)
        
        [Header(Outline ZOffset)]
        _OutlineZOffset("ZOffset (View Space)", Range(0,1)) = 0.0001
        [NoScaleOffset]_OutlineZOffsetMaskTex("    Mask (black is apply ZOffset)", 2D) = "black" {}
        _OutlineZOffsetMaskRemapStart("    RemapStart", Range(0,1)) = 0
        _OutlineZOffsetMaskRemapEnd("    RemapEnd", Range(0,1)) = 1
    }
    SubShader
    {       
        Tags 
        {
            // SRP 在 Subshader 中引入了新的 "RenderPipeline" 标签，让一个 shader 可匹配多种渲染管线；
            // 不设置该标签则匹配任意管线。若希望 SubShader 只在 URP 中运行，就把标签设为
            // "UniversalPipeline"

            // 这里必须写 "UniversalPipeline" 标签：我们只让本 shader 在 URP 中运行。
            // 若 Graphics Settings 未启用 Universal 管线，此 SubShader 会失效。

            // 可在下方再加一个 SubShader 或 Fallback 到内置 Standard，
            // 让材质同时兼容 Universal Render Pipeline 与 Builtin-RP

            // 注意：标签值是 "UniversalPipeline"，不是 "UniversalRenderPipeline"，小心写错！
            "RenderPipeline" = "UniversalPipeline"

            // 显式声明 SubShader 标签，避免混淆
            "RenderType" = "Opaque"
            "IgnoreProjector" = "True"
            "UniversalMaterialType" = "ComplexLit"
            "Queue"="Geometry"
        }
        
        // 可用 LOD 控制此 SubShader 是否被采用：
        // 若因 LOD 限制本 SubShader 不允许使用，
        // Unity 会考虑下一个 SubShader
        LOD 100
        
        // 可把各 Pass 重复的 hlsl 代码提取到这个 HLSLINCLUDE 块：重复越少，出错越少
        HLSLINCLUDE

        // 所有 Pass 都需要这个关键字
        #pragma shader_feature_local_fragment _UseAlphaClipping

        ENDHLSL

        // [#0 Pass - ForwardLit]
        // 仅前向渲染 Pass，
        // 也充当延迟渲染下的不透明前向回退。
        // 单个 Pass 内完成 GI、所有光源、阴影、自发光与雾的着色。
        // 与内置管线的前向渲染相比，URP 前向渲染多光源场景下
        // draw call 更少、overdraw 也更少。
        Pass
        {               
            Name "ForwardLit"
            Tags
            {
                // "LightMode" 需与 UniversalRenderPipeline.cs 中设置的 "ShaderPassName" 匹配； 
                // SRPDefaultUnlit 及未写 LightMode 标签的 Pass 也会由 URP 渲染

                // 要想在 URP 中渲染受光物体，"LightMode" 标签必须是 "UniversalForward"。
                "LightMode" = "UniversalForwardOnly"
            }

            // -------------------------------------
            // 渲染状态命令
            // - 显式声明渲染状态，避免混淆
            // - 如有需要，可在材质 inspector 上暴露这些渲染状态（参考 URP 的 Lit.shader）
            Blend One Zero
            ZWrite On
            Cull Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // 着色阶段
            #pragma vertex VertexShaderWork
            #pragma fragment ShadeFinalColor

            // -------------------------------------
            // 材质关键字
            // （需要的 shader_feature 已全部提取到 SubShader 级的共享 HLSLINCLUDE 块中）
            
            // -------------------------------------
            // Universal 管线关键字
            // 这一段随时可以从 URP 的 ComplexLit.shader 复制过来
            // 写自定义 shader 时，通常直接复制粘贴这些 #pragma multi_compile 即可
            // 这些 multi_compile 变体会按以下条件从构建中剥离：
            // 1) 构建时 GraphicsSettings 中所指定 URP Asset 的设置
            // 例如所有 URP Asset 都关闭了 AdditionalLights，则所有 _ADDITIONA_LIGHTS 变体
            // 都会被剥离
            // 2) 非法组合会被剥离
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            // -------------------------------------
            // Unity 定义的关键字
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            //--------------------------------------
            // GPU Instancing（GPU 实例化）
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // 宏定义（Defines）
            // - 本 Pass 只是 ForwardLitOnly，不需要任何特殊 #define
            // （无特殊 #define）

            // -------------------------------------
            // 包含（Includes）
            // - 所有着色逻辑都写在这个 .hlsl 里；记住：所有 #define 必须写在 #include 之前
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"

            ENDHLSL
        }
        
        // [#1 Pass - Outline 描边（outline）]
        // 与上面的 "ForwardLit" Pass 完全相同，只是： 
        // - 顶点位置沿法线方向外扩一点（法线外扩）
        // - 颜色再乘以描边颜色
        // - Cull Front 而非 Cull Off：任何双 Pass 描边法都必须剔除正面
        Pass 
        {
            Name "Outline"
            Tags 
            {
                // 重要：自定义 Pass（例如描边 Pass）千万不要写这行！ 
                // 否则这个描边 Pass（自定义 Pass）将不会被 URP 渲染！
                //"LightMode" = "UniversalForwardOnly" 

                // 【CPU 性能重要提示】
                // 若需要给 shader 添加自定义 Pass（描边、平面阴影、被遮挡时的 Xray 叠加层……），按以下步骤：
                // (1) 在 shader 中新增一个 Pass{}
                // (2) 在新 Pass 的 Tags{} 中写 "LightMode" = "YourCustomPassTag"
                // (3) 给渲染器添加一个自定义 RendererFeature（C#）
                // (4) 用 cmd.DrawRenderers() 绘制，ShaderPassName = "YourCustomPassTag"
                // (5) 做对了，URP 就会以利于 SRP 合批的方式渲染你的新 Pass{}（通常合成 1 个大 SRP batch）

                // 出于教学目的，目前只有 shader 文件、没有任何 C# 代码，所以这个 Outline Pass 其实并不利于 SRP 合批。
                // 若你的项目里有大量角色，务必用上面的方法让 Outline Pass 也能友好地 SRP 合批！
            }

            // -------------------------------------
            // 渲染状态命令
            // - 额外 Pass 描边法必须 Cull Front
            Blend One Zero
            ZWrite On
            Cull Front
            ZTest LEqual

            HLSLPROGRAM
            #pragma target 2.0
            
            // -------------------------------------
            // 着色阶段
            #pragma vertex VertexShaderWork
            #pragma fragment ShadeFinalColor

            // -------------------------------------
            // 材质关键字
            // （需要的 shader_feature 已全部提取到 SubShader 级的共享 HLSLINCLUDE 块中）
            
            // -------------------------------------
            // Universal 管线关键字
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _DBUFFER_MRT1 _DBUFFER_MRT2 _DBUFFER_MRT3
            #pragma multi_compile_fragment _ _LIGHT_LAYERS
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _FORWARD_PLUS
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"


            // -------------------------------------
            // Unity 定义的关键字
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ DYNAMICLIGHTMAP_ON
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            //--------------------------------------
            // GPU Instancing（GPU 实例化）
            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // 宏定义（Defines）
            // - 这是 Outline Pass，定义 "ToonShaderIsOutline"，把描边相关代码同时注入 VertexShaderWork() 和 ShadeFinalColor()
            #define ToonShaderIsOutline

            // -------------------------------------
            // 包含（Includes）
            // - 所有着色逻辑都写在这个 .hlsl 里；记住：所有 #define 必须写在 #include 之前
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"

            ENDHLSL
        }
 
        // ShadowCaster Pass：用于渲染 URP 的阴影贴图（shadow map）
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            // -------------------------------------
            // 渲染状态命令
            // 更明确地声明渲染状态，避免混淆
            ZWrite On // 本 Pass 唯一目标：写深度！
            ZTest LEqual // 尽可能在 Early-Z 阶段提前退出            
            ColorMask 0 // 不关心颜色，只想向阴影贴图写深度；ColorMask 0 可省一些写入带宽
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // 着色阶段
            #pragma vertex VertexShaderWork
            #pragma fragment AlphaClipAndLODTest // 只需 Clip()，无需着色

            // -------------------------------------
            // 材质关键字
            // - 本 Pass 唯一需要的关键字 = _UseAlphaClipping，已在 SubShader 级 HLSLINCLUDE 块中定义
            // （因此本 Pass 无需再写任何 shader_feature）

            //--------------------------------------
            // GPU Instancing（GPU 实例化）
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            // -------------------------------------
            // Unity 定义的关键字
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            // 生成阴影贴图时，用它区分平行光与点/聚光源阴影：两者施加法线偏移（Normal Bias）的公式不同
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            //--------------------------------------
            // 宏定义（Defines）
            // - 这是 ShadowCaster Pass，定义 "ToonShaderApplyShadowBiasFix"，把"消除阴影贴图瑕疵"的代码注入 VertexShaderWork()
            #define ToonShaderApplyShadowBiasFix

            // -------------------------------------
            // 包含（Includes）
            // - 所有着色逻辑都写在这个 .hlsl 里；记住：所有 #define 必须写在 #include 之前
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"

            ENDHLSL
        }

        // (X) 没有 "GBuffer" Pass

        // DepthOnly Pass：用于 URP 的离屏深度预通道（depth prepass）渲染（可在 URP 包中搜索 DepthOnlyPass.cs）
        // 例如开启深度纹理时，本 toon shader 就需要执行这个离屏深度预通道 
        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            // -------------------------------------
            // 渲染状态命令
            // 更明确地声明渲染状态，避免混淆
            ZWrite On // 本 Pass 唯一目标：写深度！
            ZTest LEqual // 尽可能在 Early-Z 阶段提前退出            
            ColorMask R // 不关心 RGB 颜色，只想写深度；ColorMask R 可省一些写入带宽
            Cull Off 
            
            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // 着色阶段
            #pragma vertex VertexShaderWork
            #pragma fragment DepthOnlyFragment // 只需 Clip()，无需颜色着色
            
            // -------------------------------------
            // 材质关键字
            // - 本 Pass 唯一需要的关键字 = _UseAlphaClipping，已在 SubShader 级 HLSLINCLUDE 块中定义
            // （因此本 Pass 无需再写任何 shader_feature）

            // -------------------------------------
            // Unity 定义的关键字
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing（GPU 实例化）
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // 宏定义（Defines）
            // - 描边区域也应写入深度：定义 "ToonShaderIsOutline"，把描边相关代码注入 VertexShaderWork()
            #define ToonShaderIsOutline

            // -------------------------------------
            // 包含（Includes）
            // - 所有着色逻辑都写在这个 .hlsl 里；记住：所有 #define 必须写在 #include 之前
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"

            ENDHLSL
        }

        // 本 Pass 用于：前向渲染器下向 _CameraNormalsTexture 绘制，或延迟渲染器下的 depth+normal 预通道。
        // 当有 renderer feature 请求时（例如 URP 的 SSAO），
        // URP 可同时生成 _CameraNormalsTexture + _CameraDepthTexture 
        Pass
        {
            Name "DepthNormalsOnly"
            Tags
            {
                "LightMode" = "DepthNormalsOnly"
            }

            // -------------------------------------
            // 渲染状态命令
            // 更明确地声明渲染状态，避免混淆
            ZWrite On // 本 Pass 唯一目标：写深度！
            ZTest LEqual // 尽可能在 Early-Z 阶段提前退出            
            ColorMask RGBA // 把法线作为 RGB 颜色绘制！
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0

            // -------------------------------------
            // 着色阶段
            #pragma vertex VertexShaderWork
            #pragma fragment DepthNormalsFragment // 只需 Clip() + 将法线以 RGB 颜色着色输出
            
            // -------------------------------------
            // 材质关键字
            // - 本 Pass 唯一需要的关键字 = _UseAlphaClipping，已在 SubShader 级 HLSLINCLUDE 块中定义
            // （因此本 Pass 无需再写任何 shader_feature）

            // -------------------------------------
            // Universal 管线关键字
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT // forward-only 变体
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            // -------------------------------------
            // Unity 定义的关键字
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            //--------------------------------------
            // GPU Instancing（GPU 实例化）
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            //--------------------------------------
            // 宏定义（Defines）

            // -------------------------------------
            // 包含（Includes）
            // - 所有着色逻辑都写在这个 .hlsl 里；记住：所有 #define 必须写在 #include 之前
            #include "SimpleURPToonLitOutlineExample_Shared.hlsl"

            ENDHLSL
        }

        // (X) 没有 "Meta" Pass
        // (X) 没有 "Universal2D" Pass
    }

    FallBack "Hidden/Universal Render Pipeline/FallbackError"
    
    // 可以自定义编辑器！推荐试试 LWGUI(https://github.com/JasonMa0012/LWGUI)
    //CustomEditor "LWGUI.LWGUI"
}
