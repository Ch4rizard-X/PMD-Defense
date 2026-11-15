// Route Defense — one-click builds: Route Defense > Build Android APK / Build Windows.
// Output goes to the project's Builds folder (Downloads\RouteDefense\Builds).
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace RouteDefense.EditorTools
{
    public static class RDBuild
    {
        static string[] Scenes() { RDSetup.Run(); return EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray(); }

        [MenuItem("Route Defense/Build Android APK")]
        public static void Android()
        {
            AndroidSetup();
            Directory.CreateDirectory("Builds");
            Report(BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = Scenes(), locationPathName = "Builds/RouteDefense.apk", target = BuildTarget.Android, options = BuildOptions.None }));
        }

        [MenuItem("Route Defense/Build and Run on phone (USB)")]
        public static void AndroidRun()
        {
            AndroidSetup();
            Directory.CreateDirectory("Builds");
            Report(BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = Scenes(), locationPathName = "Builds/RouteDefense.apk", target = BuildTarget.Android, options = BuildOptions.AutoRunPlayer }));   // installs and starts it on the plugged-in phone
        }

        // the fixed signing key (kept next to the project, never in the public repo): every build gets the same signature,
        // so a new APK installs over the old one and keeps the save. Without the key Unity signs with this PC's debug key.
        const string KEY = "signing-key-backup/routedefense.keystore", PASS = "signing-key-backup/keystore-pass.txt";
        static void AndroidSetup()
        {
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.routedefense.game");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            EditorUserBuildSettings.buildAppBundle = false;
            PlayerSettings.Android.bundleVersionCode++;   // a higher version each build, so Android installs it over the old one and keeps your save
            PlayerSettings.bundleVersion = "1." + PlayerSettings.Android.bundleVersionCode;   // the version name players see
            if (File.Exists(KEY) && File.Exists(PASS))
            {
                string pw = File.ReadAllText(PASS).Trim();
                PlayerSettings.Android.useCustomKeystore = true;
                PlayerSettings.Android.keystoreName = Path.GetFullPath(KEY); PlayerSettings.Android.keystorePass = pw;
                PlayerSettings.Android.keyaliasName = "routedefense"; PlayerSettings.Android.keyaliasPass = pw;
            }
            else { PlayerSettings.Android.useCustomKeystore = false; Debug.LogWarning("Route Defense: signing key not found in " + KEY + " - using Unity's debug key (updates won't install over other PCs' builds)"); }
        }

        [MenuItem("Route Defense/Build Windows")]
        public static void Windows()
        {
            Directory.CreateDirectory("Builds/Windows");
            Report(BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = Scenes(), locationPathName = "Builds/Windows/RouteDefense.exe", target = BuildTarget.StandaloneWindows64, options = BuildOptions.None }));
        }

        static void Report(BuildReport r)
        {
            var s = r.summary;
            if (s.result == BuildResult.Succeeded) { Debug.Log($"Route Defense: build done — {s.outputPath} ({s.totalSize / 1048576} MB)"); EditorUtility.RevealInFinder(s.outputPath); }
            else Debug.LogError($"Route Defense: build {s.result} with {s.totalErrors} errors — see the Console above");
        }
    }
}
