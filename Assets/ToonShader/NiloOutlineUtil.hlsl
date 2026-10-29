// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

#ifndef Include_NiloOutlineUtil
#define Include_NiloOutlineUtil

// 如果你的工程有更快的方式在 shader 里取相机 FOV，可以把这个慢函数换成你的方法，
// 例如在 C# 里写一个 RendererFeature 并执行 cmd.SetGlobalFloat("_CurrentCameraFOV",cameraFOV)。
// 教学 shader 图简单，保留这个更慢但更方便的取 FOV 方法
float GetCameraFOV()
{
    //https://answers.unity.com/questions/770838/how-can-i-extract-the-fov-information-from-the-pro.html
    float t = unity_CameraProjection._m11;
    float Rad2Deg = 180 / 3.1415;
    float fov = atan(1.0f / t) * 2.0 * Rad2Deg;
    return fov;
}
float ApplyOutlineDistanceFadeOut(float inputMulFix)
{
    //角色在画面里太小时，让描边（outline）淡出
    return saturate(inputMulFix);
}
float GetOutlineCameraFovAndDistanceFixMultiplier(float positionVS_Z)
{
    float cameraMulFix;
    if(unity_OrthoParams.w == 0)
    {
        ////////////////////////////////
        // 透视相机分支
        ////////////////////////////////

        // 让描边在各种相机距离下的屏幕宽度保持一致
        cameraMulFix = abs(positionVS_Z);

        // 想要平滑截止的话，可换成 tonemap 函数
        cameraMulFix = ApplyOutlineDistanceFadeOut(cameraMulFix);

        // 让描边在各种相机 FOV 下的屏幕宽度保持一致
        cameraMulFix *= GetCameraFOV();       
    }
    else
    {
        ////////////////////////////////
        // 正交相机分支
        ////////////////////////////////
        float orthoSize = abs(unity_OrthoParams.y);
        orthoSize = ApplyOutlineDistanceFadeOut(orthoSize);
        cameraMulFix = orthoSize * 50; // 50 是魔法数字，用来匹配透视相机的描边宽度
    }

    return cameraMulFix * 0.00005; // 乘常数得到默认法线外扩量(世界空间)：描边 pass 把顶点沿法线朝相机(向前)外扩出一层壳、正常 pass 原位(向后)，最终描边宽度=材质参数 _OutlineWidth × 本修正值
}
#endif

