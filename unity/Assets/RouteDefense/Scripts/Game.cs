// Route Defense — starts the game in any scene (no scene setup needed) and runs the main loop.
using UnityEngine;

namespace RouteDefense
{
    public class Game : MonoBehaviour
    {
        float saveT;

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
            Application.targetFrameRate = Save.G.smooth ? 60 : 30;   // Battery saver (default): 30 fps keeps the phone cooler
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
            if (UI.InBattle && Battle.B != null) Battle.B.Tick(dt);
            UI.Tick(dt);
            saveT += Time.unscaledDeltaTime; if (saveT > 15) { saveT = 0; Save.Write(); }
        }
        void OnApplicationPause(bool paused) { if (paused) { Save.Write(); UI.OnPause(); } }
        void OnApplicationQuit() { Save.Write(); }
    }
}
