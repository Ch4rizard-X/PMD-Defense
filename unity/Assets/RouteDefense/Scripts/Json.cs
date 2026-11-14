// Route Defense — a small JSON reader (objects -> Dictionary<string,object>, arrays -> List<object>, numbers -> double).
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;

namespace RouteDefense
{
    public static class Json
    {
        public static object Parse(string s) { int i = 0; var v = Val(s, ref i); return v; }

        static void Ws(string s, ref int i) { while (i < s.Length && char.IsWhiteSpace(s[i])) i++; }

        static object Val(string s, ref int i)
        {
            Ws(s, ref i);
            char c = s[i];
            if (c == '{') return Obj(s, ref i);
            if (c == '[') return Arr(s, ref i);
            if (c == '"') return Str(s, ref i);
            if (c == 't') { i += 4; return true; }
            if (c == 'f') { i += 5; return false; }
            if (c == 'n') { i += 4; return null; }
            int st = i;
            while (i < s.Length && "+-0123456789.eE".IndexOf(s[i]) >= 0) i++;
            return double.Parse(s.Substring(st, i - st), NumberStyles.Float, CultureInfo.InvariantCulture);
        }

        static Dictionary<string, object> Obj(string s, ref int i)
        {
            var d = new Dictionary<string, object>(); i++;
            Ws(s, ref i);
            if (s[i] == '}') { i++; return d; }
            while (true)
            {
                Ws(s, ref i); string k = Str(s, ref i); Ws(s, ref i); i++; // ':'
                d[k] = Val(s, ref i); Ws(s, ref i);
                if (s[i] == ',') { i++; continue; }
                i++; return d; // '}'
            }
        }

        static List<object> Arr(string s, ref int i)
        {
            var a = new List<object>(); i++;
            Ws(s, ref i);
            if (s[i] == ']') { i++; return a; }
            while (true)
            {
                a.Add(Val(s, ref i)); Ws(s, ref i);
                if (s[i] == ',') { i++; continue; }
                i++; return a; // ']'
            }
        }

        static string Str(string s, ref int i)
        {
            var sb = new StringBuilder(); i++;
            while (s[i] != '"')
            {
                char c = s[i++];
                if (c == '\\')
                {
                    char e = s[i++];
                    switch (e)
                    {
                        case 'n': sb.Append('\n'); break;
                        case 't': sb.Append('\t'); break;
                        case 'r': sb.Append('\r'); break;
                        case 'b': sb.Append('\b'); break;
                        case 'f': sb.Append('\f'); break;
                        case 'u': sb.Append((char)Convert.ToInt32(s.Substring(i, 4), 16)); i += 4; break;
                        default: sb.Append(e); break;
                    }
                }
                else sb.Append(c);
            }
            i++; return sb.ToString();
        }

        // helpers for reading parsed data
        public static Dictionary<string, object> O(object o) => o as Dictionary<string, object>;
        public static List<object> A(object o) => o as List<object>;
        public static int I(object o) => o == null ? 0 : Convert.ToInt32(o, CultureInfo.InvariantCulture);
        public static float F(object o) => o == null ? 0f : Convert.ToSingle(o, CultureInfo.InvariantCulture);
        public static string S(object o) => o as string ?? "";
        public static object Get(Dictionary<string, object> d, string k) => d != null && d.TryGetValue(k, out var v) ? v : null;
        public static int GI(Dictionary<string, object> d, string k) => I(Get(d, k));
        public static int[] IA(object o) { var a = A(o); if (a == null) return new int[0]; var r = new int[a.Count]; for (int i = 0; i < a.Count; i++) r[i] = I(a[i]); return r; }
        public static float[] FA(object o) { var a = A(o); if (a == null) return new float[0]; var r = new float[a.Count]; for (int i = 0; i < a.Count; i++) r[i] = F(a[i]); return r; }
    }
}
