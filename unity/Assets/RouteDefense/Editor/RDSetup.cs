// Route Defense — one-time project setup: makes the game scene, adds it to the build, sets the app name and screen rotation.
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace RouteDefense.EditorTools
{
    [InitializeOnLoad]
    public static class RDSetup
    {
        const string SCENE = "Assets/RouteDefense/RouteDefense.unity";
        static RDSetup() { EditorApplication.delayCall += Run; }

        [MenuItem("Route Defense/Set up project")]
        public static void Run()
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode) return;
            if (!File.Exists(SCENE))
            {
                var sc = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                EditorSceneManager.SaveScene(sc, SCENE);
                Debug.Log("Route Defense: made " + SCENE);
            }
            if (!EditorBuildSettings.scenes.Any(s => s.path == SCENE))
                EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene(SCENE, true) }.Concat(EditorBuildSettings.scenes.Where(s => s.path != SCENE)).ToArray();
            PlayerSettings.productName = "Route Defense";
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;
            PlayerSettings.allowedAutorotateToPortrait = true; PlayerSettings.allowedAutorotateToLandscapeLeft = true; PlayerSettings.allowedAutorotateToLandscapeRight = true;
            PlayerSettings.allowedAutorotateToPortraitUpsideDown = false;
            // pixel art and menu colours as authored (Linear brightens every UI colour)
            if (PlayerSettings.colorSpace != ColorSpace.Gamma) { PlayerSettings.colorSpace = ColorSpace.Gamma; Debug.Log("Route Defense: colour space set to Gamma"); }
            if (EditorSceneManager.GetActiveScene().path != SCENE && string.IsNullOrEmpty(EditorSceneManager.GetActiveScene().path))
                EditorSceneManager.OpenScene(SCENE);
        }
    }
}
