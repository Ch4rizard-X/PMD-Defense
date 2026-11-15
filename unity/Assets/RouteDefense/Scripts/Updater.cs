// Route Defense — full app updates for the Android build.
// Small balance changes arrive through settings.json (Config.cs). Code changes need a new APK: on launch the game reads
// apk.json (newest version number, download link, size, SHA-256), and if it is newer than this app the title screen
// offers "Update". The APK downloads into the game's files folder, its SHA-256 is checked, then Android's installer
// opens and the player taps Install. Same signing key on every build, so the save stays.
using System;
using System.Collections;
using System.IO;
using System.Security.Cryptography;
using System.Threading.Tasks;
using UnityEngine;
using UnityEngine.Networking;

namespace RouteDefense
{
    [Serializable]
    public class ApkInfo
    {
        public int versionCode;      // must be higher than the installed app's
        public string version = "";  // shown to the player
        public string url = "";      // direct download of the APK
        public long bytes;           // size, for the progress bar
        public string sha256 = "";   // checked before installing; a broken download never reaches the installer
        public string notes = "";    // what changed
    }

    public static class Updater
    {
        public const string INFO_URL = "https://raw.githubusercontent.com/Ch4rizard-X/pmd-defense/main/settings/apk.json";
        public static ApkInfo Latest;            // set when a newer APK is online
        public static bool Checked, Busy;
        public static float Progress;            // 0..1 while downloading
        public static string Status = "";

        static string ApkPath => Path.Combine(Application.persistentDataPath, "update.apk");
        // an optional access token kept only in this project's Resources (never in the public repo), for a private download
        static string Token { get { var t = Resources.Load<TextAsset>("Data/upd_token"); return t != null ? t.text.Trim() : ""; } }

#if UNITY_ANDROID && !UNITY_EDITOR
        static AndroidJavaObject Act => new AndroidJavaClass("com.unity3d.player.UnityPlayer").GetStatic<AndroidJavaObject>("currentActivity");
        static AndroidJavaClass J => new AndroidJavaClass("com.routedefense.RDInstall");
        public static long Installed { get { try { return J.CallStatic<long>("versionCode", Act); } catch { return 0; } } }
        public static bool CanInstall { get { try { return J.CallStatic<bool>("canInstall", Act); } catch { return true; } } }
        public static void AskPermission() { try { J.CallStatic("askPermission", Act); } catch (Exception e) { Debug.LogWarning(e); } }
        static string OpenInstaller() { try { return J.CallStatic<string>("install", Act); } catch (Exception e) { return e.Message; } }
        public static bool Supported => true;
#else
        public static long Installed => 0;
        public static bool CanInstall => false;
        public static void AskPermission() { }
        static string OpenInstaller() => "updates install only on Android";
        public static bool Supported => false;
#endif

        // reads apk.json; done(true) when a newer APK is online
        public static IEnumerator Check(Action<bool> done = null)
        {
            if (!Supported) { Checked = true; done?.Invoke(false); yield break; }
            using (var r = UnityWebRequest.Get(INFO_URL + "?t=" + DateTime.UtcNow.Ticks))
            {
                r.timeout = 10; yield return r.SendWebRequest();
                Checked = true;
                if (r.result != UnityWebRequest.Result.Success) { Status = "Couldn't check (offline?)"; done?.Invoke(false); yield break; }
                ApkInfo i = null; try { i = JsonUtility.FromJson<ApkInfo>(r.downloadHandler.text); } catch { }
                if (i == null || i.versionCode <= 0 || string.IsNullOrEmpty(i.url)) { Status = "No update online yet"; done?.Invoke(false); yield break; }
                bool newer = i.versionCode > Installed;
                Latest = newer ? i : null; Status = newer ? "Update " + i.version + " is ready" : "Up to date";
                done?.Invoke(newer);
            }
        }

        // downloads and checks the APK; done(null) when it is ready to install, otherwise done(error)
        public static IEnumerator Download(ApkInfo i, Action<string> done)
        {
            if (Busy) yield break; Busy = true; Progress = 0;
            string url = i.url, tok = Token;
            if (tok != "")
            {
                // private GitHub file: ask with the token, then follow the redirect without it (the storage link refuses extra sign-ins)
                using (var r = UnityWebRequest.Get(url))
                {
                    r.SetRequestHeader("Authorization", "Bearer " + tok); r.SetRequestHeader("Accept", "application/octet-stream");
                    r.redirectLimit = 0; r.timeout = 20; yield return r.SendWebRequest();
                    string loc = r.GetResponseHeader("Location");
                    if (string.IsNullOrEmpty(loc)) { Busy = false; done("Download link refused (" + r.responseCode + ")"); yield break; }
                    url = loc;
                }
            }
            try { if (File.Exists(ApkPath)) File.Delete(ApkPath); } catch { }
            using (var r = new UnityWebRequest(url, UnityWebRequest.kHttpVerbGET))
            {
                r.downloadHandler = new DownloadHandlerFile(ApkPath) { removeFileOnAbort = true };
                var op = r.SendWebRequest();
                while (!op.isDone) { Progress = i.bytes > 0 ? Mathf.Clamp01(r.downloadedBytes / (float)i.bytes) : r.downloadProgress; yield return null; }
                if (r.result != UnityWebRequest.Result.Success) { Busy = false; done("Download failed: " + r.error); yield break; }
            }
            Progress = 1; Status = "Checking the download...";
            var hash = Task.Run(() => { using (var s = File.OpenRead(ApkPath)) using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(s)).Replace("-", "").ToLowerInvariant(); });
            while (!hash.IsCompleted) yield return null;
            Busy = false;
            if (hash.IsFaulted) { done("Couldn't read the download"); yield break; }
            if (!string.IsNullOrEmpty(i.sha256) && hash.Result != i.sha256.ToLowerInvariant()) { try { File.Delete(ApkPath); } catch { } done("The download was damaged - try again"); yield break; }
            done(null);
        }

        public static bool Downloaded(ApkInfo i) => File.Exists(ApkPath) && (i.bytes <= 0 || new FileInfo(ApkPath).Length == i.bytes);
        public static string Install() { Save.Write(); return OpenInstaller(); }   // save first: the installer closes the game

        // after updating, the old APK is not needed any more
        public static void CleanUp() { try { if (File.Exists(ApkPath) && (Latest == null)) File.Delete(ApkPath); } catch { } }
    }
}
