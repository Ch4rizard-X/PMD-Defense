// Route Defense — starts the game in any scene (no scene setup needed) and runs the main loop.
using UnityEngine;
using UnityEngine.Rendering;

namespace RouteDefense
{
    public class Game : MonoBehaviour
    {
        float saveT; static float resT;

        // Lower resolution (option, on by default): draws fewer pixels on phones, about 720 on the short side (never more than the screen has),
        // and the phone stretches the picture up. Most of the heat comes from the number of pixels drawn each frame.
        const int SAVER_SHORT = 720;
        // the game's full drawing size, taken once at launch before any change (so a smaller size can never shrink again)
        static int natL, natS;
        static void ReadNative()
        {
            if (natL > 0) return;
            natL = Mathf.Max(Screen.width, Screen.height); natS = Mathf.Min(Screen.width, Screen.height);
        }
        public static float RenderScale() { if (!Application.isMobilePlatform) return 1f; ReadNative(); return natS > 0 ? Mathf.Min(1f, Mathf.Min(Screen.width, Screen.height) / (float)natS) : 1f; }
        public static void ApplyResolution()
        {
            if (!Application.isMobilePlatform || Save.G == null) return; ReadNative(); if (natS <= 0) return;
            bool land = Screen.width > Screen.height; int w, h;
            if (!Save.G.lowres) { w = land ? natL : natS; h = land ? natS : natL; }
            else
            {
                // keep the window's current shape, only fewer pixels
                float aspect = Mathf.Max(Screen.width, Screen.height) / (float)Mathf.Max(1, Mathf.Min(Screen.width, Screen.height));
                int S = Mathf.Min(natS, SAVER_SHORT), L = Mathf.RoundToInt(S * aspect);
                w = land ? L : S; h = land ? S : L;
            }
            if (Mathf.Abs(Screen.width - w) > 2 || Mathf.Abs(Screen.height - h) > 2) Screen.SetResolution(w, h, FullScreenMode.FullScreenWindow);
        }

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Boot()
        {
            if (FindFirstObjectByType<Game>() != null) return;
            var go = new GameObject("RouteDefense"); DontDestroyOnLoad(go); go.AddComponent<Game>();
        }

        void Awake()
        {
            Application.targetFrameRate = 60;
            Screen.autorotateToPortrait = Screen.autorotateToLandscapeLeft = Screen.autorotateToLandscapeRight = true;
            Screen.autorotateToPortraitUpsideDown = false; Screen.orientation = ScreenOrientation.AutoRotation;
            DB.LoadAll(); Save.Load();
            Application.targetFrameRate = Save.G.smooth ? 60 : 30;   // the 60 fps option (on by default); 30 fps is cooler but choppier
            ApplyResolution();
            Cfg.LoadCached(); StartCoroutine(Cfg.Fetch());   // balance numbers: last downloaded copy now, a fresh one in the background
            gameObject.AddComponent<AudioListener>();   // the scene has no camera with one
            Gfx.InitAudio(gameObject);
            UI.View = new GameObject("BattleView").AddComponent<BattleView>(); UI.View.transform.SetParent(transform);
#if ENABLE_INPUT_SYSTEM
            // this project uses the Input System package: give the menus an event system that reads it
            if (FindFirstObjectByType<UnityEngine.EventSystems.EventSystem>() == null)
            {
                var es = new GameObject("EventSystem"); es.transform.SetParent(transform);
                es.AddComponent<UnityEngine.EventSystems.EventSystem>(); es.AddComponent<UnityEngine.InputSystem.UI.InputSystemUIInputModule>();
            }
#endif
            UI.Init(gameObject);
            UI.ShowTitle();
        }
        void Update()
        {
            float dt = Mathf.Min(0.05f, Time.deltaTime);
            resT += Time.unscaledDeltaTime; if (resT > 0.5f) { resT = 0; ApplyResolution(); }   // turning the phone can reset the drawing size
            // Idle slowdown: in menus, while paused and between waves, once you haven't touched the screen for 1.5 s,
            // only about 10 frames a second are drawn. The game keeps running and reacts to a touch at full speed right away.
            var Bt = Battle.B; bool fighting = UI.InBattle && Bt != null && !Bt.paused && Bt.phase == "wave";
            bool touched = Time.unscaledTime - UI.LastInput < 1.5f; int full = Save.G.smooth ? 60 : 30;
            OnDemandRendering.renderFrameInterval = fighting || touched ? 1 : Mathf.Max(1, full / 10);
            if (UI.InBattle && Battle.B != null) Battle.B.Tick(dt);
            UI.Tick(dt);
            saveT += Time.unscaledDeltaTime; if (saveT > 15) { saveT = 0; Save.Write(); }
        }
        void OnApplicationPause(bool paused) { if (paused) { Save.Write(); UI.OnPause(); } }
        void OnApplicationQuit() { Save.Write(); }
    }
}
