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
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.routedefense.game");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            EditorUserBuildSettings.buildAppBundle = false;
            PlayerSettings.Android.bundleVersionCode++;   // a higher version each build, so Android installs it over the old one and keeps your save
            Directory.CreateDirectory("Builds");
            Report(BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = Scenes(), locationPathName = "Builds/RouteDefense.apk", target = BuildTarget.Android, options = BuildOptions.None }));
        }

        [MenuItem("Route Defense/Build and Run on phone (USB)")]
        public static void AndroidRun()
        {
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.routedefense.game");
            PlayerSettings.SetScriptingBackend(NamedBuildTarget.Android, ScriptingImplementation.IL2CPP);
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            EditorUserBuildSettings.buildAppBundle = false; PlayerSettings.Android.bundleVersionCode++;
            Directory.CreateDirectory("Builds");
            Report(BuildPipeline.BuildPlayer(new BuildPlayerOptions { scenes = Scenes(), locationPathName = "Builds/RouteDefense.apk", target = BuildTarget.Android, options = BuildOptions.AutoRunPlayer }));   // installs and starts it on the plugged-in phone
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
