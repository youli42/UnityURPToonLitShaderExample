using UnityEngine;

/// <summary>
/// ToonDemo 场景的学习辅助脚本（IMGUI，不依赖任何外部资源）：
/// - 说明每个内置图元演示了哪个参数
/// - A/D 旋转主光源，观察赛璐璐明暗分界如何随之移动
/// - O 开关全部 toon 材质的描边，方便对比
/// </summary>
public class ToonDemoHint : MonoBehaviour
{
    const string ToonShaderName = "SimpleURPToonLitExample(With Outline)";

    Light _mainLight;
    bool _outlineEnabled = true;
    float _lightYaw = -30f;

    void Start()
    {
        _mainLight = FindLight();
    }

    static Light FindLight()
    {
        foreach (var l in Object.FindObjectsOfType<Light>())
        {
            if (l.type == LightType.Directional) return l;
        }
        return null;
    }

    void Update()
    {
        // 旧版 Input Manager 足够学习用，不引入新 Input System
        if (Input.GetKeyDown(KeyCode.O))
        {
            _outlineEnabled = !_outlineEnabled;
            ApplyOutline(_outlineEnabled);
        }

        if (_mainLight != null)
        {
            if (Input.GetKey(KeyCode.A)) _lightYaw -= 60f * Time.deltaTime;
            if (Input.GetKey(KeyCode.D)) _lightYaw += 60f * Time.deltaTime;
            _mainLight.transform.rotation = Quaternion.Euler(50f, _lightYaw, 0f);
        }
    }

    /// <summary>把场景内所有 toon 材质的 _OutlineWidth 设为 0 或恢复。</summary>
    static void ApplyOutline(bool on)
    {
        var shader = Shader.Find(ToonShaderName);
        if (shader == null) return;
        foreach (var renderer in Object.FindObjectsOfType<Renderer>())
        {
            var materials = renderer.sharedMaterials;
            for (int i = 0; i < materials.Length; ++i)
            {
                var mat = materials[i];
                if (mat == null || mat.shader != shader) continue;
                float width = on ? Mathf.Max(mat.GetFloat("_OutlineWidth"), 1.5f) : 0f;
                mat.SetFloat("_OutlineWidth", width);
            }
        }
    }

    void OnGUI()
    {
        GUILayout.BeginArea(new Rect(16f, 16f, 430f, 260f));
        GUILayout.Label("URP Toon Lit 学习场景（仅使用 Unity 内置图元）");
        GUILayout.Label("Sphere   —— 硬边明暗：_CelShadeSoftness ≈ 0.02");
        GUILayout.Label("Capsule  —— 软边明暗：_CelShadeSoftness ≈ 0.35");
        GUILayout.Label("Cylinder —— 亮部更大：_CelShadeMidPoint ≈ -0.8");
        GUILayout.Label("Cube     —— 粗描边：_OutlineWidth ≈ 3");
        GUILayout.Label("Ground   —— 不描边：_OutlineWidth = 0");
        GUILayout.Space(8);
        GUILayout.Label("操作：A / D 旋转主光源，O 开关描边");
        GUILayout.Label("描边：" + (_outlineEnabled ? "开" : "关"));
        GUILayout.EndArea();
    }
}
