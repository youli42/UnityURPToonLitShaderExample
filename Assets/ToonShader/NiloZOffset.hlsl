// For more information, visit -> https://github.com/ColinLeung-NiloCat/UnityURPToonLitShaderExample

#ifndef Include_NiloZOffset
#define Include_NiloZOffset

// 在视图空间（线性、以视图空间为单位）把一个"虚拟顶点"朝相机方向推，
// 然后只用虚拟顶点算出的 positionCS.z 覆写原顶点的 positionCS.z
// 只影响顶点着色器阶段 ZTest/ZWrite 的深度值，真实几何不动

// 用途：
// -把描边（outline）壳朝相机推，避免脸上/眼上的描边被相邻几何遮挡产生穿模
// -让眉毛渲染在头发之上
// -不移动几何体解决 ZFighting（深度冲突），等效深度偏移（depth bias），偏移量由材质参数传入
float4 NiloGetNewClipPosWithZOffset(float4 originalPositionCS, float viewSpaceZOffsetAmount)
{
    if(unity_OrthoParams.w == 0)
    {
        ////////////////////////////////
        // 透视相机分支
        ////////////////////////////////
        float2 ProjM_ZRow_ZW = UNITY_MATRIX_P[2].zw;
        float modifiedPositionVS_Z = -originalPositionCS.w + -viewSpaceZOffsetAmount; // 推"虚拟顶点"靠近相机
        float modifiedPositionCS_Z = modifiedPositionVS_Z * ProjM_ZRow_ZW[0] + ProjM_ZRow_ZW[1];
        originalPositionCS.z = modifiedPositionCS_Z * originalPositionCS.w / (-modifiedPositionVS_Z); // 覆写 positionCS.z
        return originalPositionCS;    
    }
    else
    {
        ////////////////////////////////
        // 正交相机分支
        ////////////////////////////////
        originalPositionCS.z += -viewSpaceZOffsetAmount / _ProjectionParams.z; // 推虚拟顶点并覆写 positionCS.z
        return originalPositionCS;
    }
}

#endif

