// Route Defense — balance settings that can be updated online without rebuilding the app.
// On launch the game uses the last downloaded copy (or these defaults), then fetches settings.json from SETTINGS_URL
// in the background; the new numbers apply from the next battle. Only numbers live here: no code, sprites or music.
using System;
using System.Collections;
using System.IO;
using UnityEngine;
using UnityEngine.Networking;

namespace RouteDefense
{
    [Serializable]
    public class RDConfig
    {
        public int version = 1;
        // battle length: waves at tier 1 on every map, and extra waves per tier
        public int waveBase = 40, waveStep = 1;
        // map groups (Beginner, Intermediate, Advanced, Expert): tiers added to every fight, reward multiplier,
        // wild Pokémon per wave multiplier, and the tier to clear on any map of the group before to open the group
        public int[] groupAdd = { 0, 4, 13, 27 };
        public float[] groupPay = { 1f, 1.1f, 1.2f, 1.35f };
        public float[] groupCount = { 1f, 1.05f, 1.1f, 1.15f };
        public int[] groupGate = { 0, 5, 10, 15 };
        // level curve: how much harder each tier step is, wild levels per step, and the spread between the lowest and highest wild level
        public float threatStep = 2.05f / 4.2f, lvPerThreat = 4.2f, lvSpread = 3f, lvSpreadPerThreat = 0.3f;
        // XP: overall multiplier; full XP up to xpFullGap levels above the wild Pokémon, none at xpZeroGap levels above
        public float xpMul = 0.4f, xpFullGap = 5f, xpZeroGap = 15f;
        // upgrades of placed Pokémon: bonus per level, number of levels, cost of each level as a share of the placing cost
        public float upgStep = 0.08f; public int upgMax = 5; public float[] upgCost = { 0.8f, 1.2f, 1.8f, 2.6f, 3.6f };
        // spawn weight by rarity (Common, Uncommon, Rare, Very rare by catch rate)
        public float[] rarity = { 1f, 0.6f, 0.35f, 0.15f };
        // weather lasts this many waves (plus Rescue tree bonuses)
        public int weatherWaves = 3;
        // battle cash at the start, and ₽ for a win (both grow with the fight's threat)
        public int startCash = 220, startCashPerThreat = 60, winPay = 100, winPayPerThreat = 80;
    }

    public static class Cfg
    {
        // the public settings file (raw link); empty = only the built-in numbers and the last downloaded copy
        public const string SETTINGS_URL = "https://raw.githubusercontent.com/Ch4rizard-X/PMD-Defense/main/settings/settings.json";
        public static RDConfig C = new RDConfig();
        public static string Status = "built-in";
        static string CachePath => Path.Combine(Application.persistentDataPath, "settings.json");

        public static void LoadCached()
        {
            try { if (File.Exists(CachePath)) { var c = JsonUtility.FromJson<RDConfig>(File.ReadAllText(CachePath)); if (Valid(c)) { C = c; Status = "saved copy v" + c.version; } } }
            catch (Exception ex) { Debug.LogWarning("Route Defense: saved settings unreadable, using built-in ones (" + ex.Message + ")"); }
        }

        public static IEnumerator Fetch()
        {
            if (string.IsNullOrEmpty(SETTINGS_URL)) yield break;
            using (var r = UnityWebRequest.Get(SETTINGS_URL + "?t=" + DateTime.UtcNow.Ticks))   // the query string skips stale caches
            {
                r.timeout = 10; yield return r.SendWebRequest();
                if (r.result != UnityWebRequest.Result.Success) { Debug.Log("Route Defense: settings not updated (offline?) - " + r.error); yield break; }
                string txt = r.downloadHandler.text; RDConfig c = null;
                try { c = JsonUtility.FromJson<RDConfig>(txt); } catch { }
                if (!Valid(c)) { Debug.LogWarning("Route Defense: downloaded settings were not valid, keeping the current ones"); yield break; }
                C = c; Status = "online v" + c.version;
                try { File.WriteAllText(CachePath, txt); } catch { }
                Debug.Log("Route Defense: settings updated to version " + c.version);
            }
        }

        // a broken or half-written file must never break the game
        static bool Valid(RDConfig c) => c != null && c.version >= 1 && c.waveBase > 0 && c.groupAdd != null && c.groupAdd.Length == 4 && c.groupPay != null && c.groupPay.Length == 4
            && c.groupCount != null && c.groupCount.Length == 4 && c.groupGate != null && c.groupGate.Length == 4 && c.upgCost != null && c.upgCost.Length >= c.upgMax
            && c.rarity != null && c.rarity.Length == 4 && c.lvPerThreat > 0 && c.threatStep > 0 && c.xpZeroGap > c.xpFullGap;
    }
}
