using System;
using System.IO;
using System.Reflection;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace ToonLearning.Editor
{
    /// <summary>
    /// 一键把本仓库补齐成可运行的 URP 学习工程：
    ///   1) 生成 URP 管线资产 + 渲染器资产并挂到 Graphics/Quality Settings
    ///   2) 用 Unity 内置图元（Plane/Sphere/Capsule/Cylinder/Cube）搭一个 ToonDemo 场景
    /// 全部方法幂等，可重复执行；供 Unity 命令行 -executeMethod 调用。
    /// </summary>
    public static class ToonProjectBootstrap
    {
        const string SettingsFolder = "Assets/Settings";
        const string MaterialsFolder = "Assets/Materials";
        const string ScenesFolder = "Assets/Scenes";
        const string PipelineAssetPath = SettingsFolder + "/URP-ToonDemo.asset";
        static string RendererAssetPath = SettingsFolder + "/URP-ToonDemo_Renderer.asset";
        const string DemoScenePath = ScenesFolder + "/ToonDemo.unity";
        const string ToonShaderName = "SimpleURPToonLitExample(With Outline)";

        const BindingFlags InternalStatic = BindingFlags.Static | BindingFlags.NonPublic | BindingFlags.Public;

        /// <summary>
        /// URP 的若干创建入口是 internal API，这里用反射调用，避免手写 YAML 资产。
        /// 支持省略带默认值的尾随参数。
        /// </summary>
        static object InvokeInternal(string typeName, string methodName, params object[] args)
        {
            var type = Type.GetType(typeName + ", Unity.RenderPipelines.Universal.Editor")
                       ?? Type.GetType(typeName + ", Unity.RenderPipelines.Universal.Runtime");
            if (type == null)
                throw new InvalidOperationException("找不到类型：" + typeName);

            foreach (var method in type.GetMethods(InternalStatic))
            {
                if (method.Name != methodName) continue;
                var parameters = method.GetParameters();
                if (parameters.Length < args.Length) continue;

                var full = new object[parameters.Length];
                bool ok = true;
                for (int i = 0; i < parameters.Length; ++i)
                {
                    if (i < args.Length) { full[i] = args[i]; continue; }
                    if (!parameters[i].HasDefaultValue) { ok = false; break; }
                    full[i] = parameters[i].DefaultValue;
                }
                if (!ok) continue;

                return method.Invoke(null, full);
            }
            throw new InvalidOperationException($"找不到可调用的方法 {typeName}.{methodName}");
        }

        static void EnsureFolder(string folder)
        {
            if (AssetDatabase.IsValidFolder(folder)) return;
            var parent = Path.GetDirectoryName(folder)?.Replace('\\', '/');
            var name = Path.GetFileName(folder);
            if (string.IsNullOrEmpty(parent))
                AssetDatabase.CreateFolder("Assets", name);
            else
                AssetDatabase.CreateFolder(parent, name);
        }

        [MenuItem("Toon Learning/Setup/1. 生成 URP 管线资产")]
        public static void SetupPipeline()
        {
            EnsureFolder(SettingsFolder);

            // 渲染器资产：交给 URP 内部工厂生成（它会顺带填好 postProcessData 等默认引用）
            // relativePath 必须为 true，由 URP 推导路径与扩展名；.data 后缀会被 CreateAsset 拒绝
            var rendererData = AssetDatabase.LoadAssetAtPath<ScriptableRendererData>(RendererAssetPath);
            if (rendererData == null)
            {
                rendererData = InvokeInternal("UnityEngine.Rendering.Universal.UniversalRenderPipelineAsset", "CreateRendererAsset",
                    PipelineAssetPath, RendererType.UniversalRenderer, true, (object)"Renderer") as ScriptableRendererData;
                AssetDatabase.SaveAssets();
                AssetDatabase.Refresh();
                RendererAssetPath = AssetDatabase.GetAssetPath(rendererData);
                Debug.Log("已生成渲染器资产：" + RendererAssetPath);
            }

            // 管线资产
            var pipeline = AssetDatabase.LoadAssetAtPath<UniversalRenderPipelineAsset>(PipelineAssetPath);
            if (pipeline == null)
            {
                pipeline = UniversalRenderPipelineAsset.Create(rendererData);
                AssetDatabase.CreateAsset(pipeline, PipelineAssetPath);
                Debug.Log("已生成管线资产：" + PipelineAssetPath);
            }

            // 强制把渲染器登记为默认渲染器（重跑或资产缺失引用时的自愈）
            var rso = new SerializedObject(pipeline);
            var list = rso.FindProperty("m_RendererDataList");
            if (list != null)
            {
                list.arraySize = 1;
                list.GetArrayElementAtIndex(0).objectReferenceValue = rendererData;
            }
            Set(rso, "m_DefaultRendererIndex", 0);
            rso.ApplyModifiedPropertiesWithoutUndo();

            // 学习用途的最小配置：主光源阴影 + 级联
            var so = new SerializedObject(pipeline);
            Set(so, "m_Shadows", true);
            Set(so, "m_MainShadowFilterMethod", 1);           // High Quality 降噪
            Set(so, "m_ShadowDepthBias", 1.0f);
            Set(so, "m_ShadowNormalBias", 1.0f);
            Set(so, "m_AdditionalLightsShadowResolutionTierLow", 512);
            so.ApplyModifiedPropertiesWithoutUndo();

            // URP Global Settings：该类型是 internal，只能反射调用其 Ensure（已存在则直接返回，幂等）
            InvokeInternal("UnityEngine.Rendering.Universal.UniversalRenderPipelineGlobalSettings", "Ensure", "Settings");

            GraphicsSettings.defaultRenderPipeline = pipeline;
            for (int i = 0; i < QualitySettings.names.Length; ++i)
            {
                QualitySettings.SetQualityLevel(i, false);
                QualitySettings.renderPipeline = pipeline;
            }

            AssetDatabase.SaveAssets();
            AssetDatabase.Refresh();
            Debug.Log("URP 管线配置完成。");
        }

        static void Set(SerializedObject so, string property, object value)
        {
            var p = so.FindProperty(property);
            if (p == null) return; // 字段名随 URP 版本变化时跳过，不影响主流程
            switch (p.propertyType)
            {
                case SerializedPropertyType.Boolean: p.boolValue = Convert.ToBoolean(value); break;
                case SerializedPropertyType.Integer: p.intValue = Convert.ToInt32(value); break;
                case SerializedPropertyType.Float: p.floatValue = Convert.ToSingle(value); break;
            }
        }

        [MenuItem("Toon Learning/Setup/2. 生成 Demo 场景与材质")]
        public static void SetupScene()
        {
            SetupPipeline();
            EnsureFolder(MaterialsFolder);
            EnsureFolder(ScenesFolder);

            var shader = Shader.Find(ToonShaderName);
            if (shader == null)
                throw new InvalidOperationException("找不到 shader：" + ToonShaderName + "（请确认 Assets/ToonShader 已被导入）");

            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);

            // 摄像机
            var cameraGO = new GameObject("Main Camera", typeof(Camera), typeof(AudioListener));
            cameraGO.tag = "MainCamera";
            cameraGO.transform.position = new Vector3(0f, 2.6f, -9f);
            cameraGO.transform.rotation = Quaternion.Euler(12f, 0f, 0f);
            var cam = cameraGO.GetComponent<Camera>();
            cam.clearFlags = CameraClearFlags.Skybox;
            cam.nearClipPlane = 0.1f;
            cam.farClipPlane = 200f;

            // 主方向光：赛璐璐的分层依赖阴影，务必开阴影
            var lightGO = new GameObject("Directional Light", typeof(Light));
            lightGO.transform.rotation = Quaternion.Euler(50f, -30f, 0f);
            var light = lightGO.GetComponent<Light>();
            light.type = LightType.Directional;
            light.color = Color.white;
            light.intensity = 2.2f;
            light.shadows = LightShadows.Soft;
            light.shadowStrength = 1f;
            light.shadowBias = 0.03f;
            light.shadowNormalBias = 0.2f;

            // 地面：不加描边，避免图元接缝
            var ground = CreatePrimitive(PrimitiveType.Plane, "Ground", new Vector3(0f, 0f, 0f));
            ground.transform.localScale = new Vector3(3f, 1f, 3f);
            var groundMat = ToonMaterial("Toon_Ground", new Color(0.72f, 0.72f, 0.7f));
            groundMat.SetFloat("_OutlineWidth", 0f);
            Apply(groundMat, ground);

            // 一排内置图元，逐个展示 toon 关键参数的差别
            var demos = new[]
            {
                new Demo(PrimitiveType.Sphere,   "Sphere_HardEdge",  new Color(0.95f, 0.55f, 0.45f), -0.5f, 0.02f, 1.5f, 0.5f),
                new Demo(PrimitiveType.Capsule,  "Capsule_SoftEdge", new Color(0.45f, 0.72f, 0.95f), -0.4f, 0.35f, 1.5f, 1.0f),
                new Demo(PrimitiveType.Cylinder, "Cylinder_LitArea", new Color(0.55f, 0.85f, 0.55f), -0.8f, 0.05f, 1.5f, 1.0f),
                new Demo(PrimitiveType.Cube,     "Cube_Outline",     new Color(0.9f, 0.8f, 0.35f),  -0.5f, 0.05f, 3.0f, 1.0f),
            };

            float x = -3.6f;
            foreach (var d in demos)
            {
                var go = CreatePrimitive(d.Type, d.Name, new Vector3(x, d.Y, 0f));
                var mat = ToonMaterial("Toon_" + d.Name, d.Color);
                mat.SetFloat("_CelShadeMidPoint", d.MidPoint);
                mat.SetFloat("_CelShadeSoftness", d.Softness);
                mat.SetFloat("_OutlineWidth", d.Outline);
                mat.SetColor("_OutlineColor", new Color(0.12f, 0.1f, 0.15f));
                mat.SetColor("_ShadowMapColor", new Color(1f, 0.825f, 0.78f));
                mat.SetFloat("_ReceiveShadowMappingAmount", 0.65f);
                Apply(mat, go);
                x += 2.4f;
            }

            // 说明牌（IMGUI 即可，不引入外部字体/预制体）；用 Type.GetType 避免对运行程序集的编译期依赖
            var hud = new GameObject("ToonDemoHUD");
            var hintType = Type.GetType("ToonDemoHint, Assembly-CSharp");
            if (hintType != null) hud.AddComponent(hintType);

            EditorSceneManager.MarkSceneDirty(scene);
            EditorSceneManager.SaveScene(scene, DemoScenePath);
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(DemoScenePath, true) };
            AssetDatabase.SaveAssets();
            Debug.Log("已生成场景：" + DemoScenePath);
        }

        static GameObject CreatePrimitive(PrimitiveType type, string name, Vector3 position)
        {
            var go = GameObject.CreatePrimitive(type);
            go.name = name;
            go.transform.position = position;
            return go;
        }

        /// <summary>创建/复用 toon 材质；BaseMap 留空（white），只用纯色，方便观察光照分层。</summary>
        static Material ToonMaterial(string name, Color baseColor)
        {
            var path = $"{MaterialsFolder}/{name}.mat";
            var mat = AssetDatabase.LoadAssetAtPath<Material>(path);
            if (mat == null)
            {
                mat = new Material(Shader.Find(ToonShaderName)) { name = name };
                AssetDatabase.CreateAsset(mat, path);
            }
            mat.shader = Shader.Find(ToonShaderName);
            mat.SetColor("_BaseColor", baseColor);
            EditorUtility.SetDirty(mat);
            return mat;
        }

        static void Apply(Material mat, GameObject go)
        {
            var renderer = go.GetComponent<Renderer>();
            renderer.sharedMaterial = mat;
            // 内置图元默认关闭了接收阴影之外的设置，这里保持默认即可
        }

        struct Demo
        {
            public PrimitiveType Type;
            public string Name;
            public Color Color;
            public float MidPoint;   // 明暗分界位置（-1~1，越小亮部越大）
            public float Softness;   // 分界软硬
            public float Outline;    // 描边粗细
            public float Y;          // 离地高度，让图元正好放在地面上
            public Demo(PrimitiveType t, string n, Color c, float m, float s, float o, float y)
            {
                Type = t; Name = n; Color = c; MidPoint = m; Softness = s; Outline = o; Y = y;
            }
        }

        [MenuItem("Toon Learning/Setup/3. 一键完成（管线 + 场景）")]
        public static void SetupAll()
        {
            SetupScene();
        }

        /// <summary>
        /// 离线渲染一张 ToonDemo 截图到 Docs/screenshots/，用于确认管线与材质真的出图。
        /// 需要真实图形设备：用 -batchmode（不要加 -nographics）执行。
        /// </summary>
        [MenuItem("Toon Learning/Setup/4. 渲染截图验证")]
        public static void CapturePreview()
        {
            const int width = 1280;
            const int height = 720;

            var scene = EditorSceneManager.OpenScene(DemoScenePath, OpenSceneMode.Single);
            var cam = Camera.main;
            if (cam == null)
                throw new InvalidOperationException("场景中没有 Main Camera");

            cam.transform.position = new Vector3(0f, 2.8f, -9.5f);
            cam.transform.rotation = Quaternion.Euler(14f, 0f, 0f);

            var rt = new RenderTexture(width, height, 24) { antiAliasing = 2 };
            rt.Create();
            cam.targetTexture = rt;
            cam.Render();

            var previous = RenderTexture.active;
            RenderTexture.active = rt;
            var tex = new Texture2D(width, height, TextureFormat.RGB24, false);
            tex.ReadPixels(new Rect(0, 0, width, height), 0, 0);
            tex.Apply();
            RenderTexture.active = previous;

            cam.targetTexture = null;
            UnityEngine.Object.DestroyImmediate(rt);

            var root = Directory.GetParent(Application.dataPath).FullName.Replace('\\', '/');
            var outDir = root + "/Docs/screenshots";
            Directory.CreateDirectory(outDir);
            File.WriteAllBytes(outDir + "/toon-demo.png", tex.EncodeToPNG());
            UnityEngine.Object.DestroyImmediate(tex);
            Debug.Log("截图已输出：" + outDir + "/toon-demo.png");
        }
    }
}
