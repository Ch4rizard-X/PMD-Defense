// Route Defense — adds what the in-game updater needs to the Android manifest while Unity builds the APK:
// permission to open Android's installer, and the private link (RDInstall) that hands it the downloaded APK.
using System.IO;
using System.Xml;
using UnityEditor;
using UnityEditor.Android;
using UnityEditor.Build;

namespace RouteDefense.EditorTools
{
    public class RDGradle : IPostGenerateGradleAndroidProject
    {
        public int callbackOrder => 0;
        const string NS = "http://schemas.android.com/apk/res/android";

        public void OnPostGenerateGradleAndroidProject(string path)
        {
            string f = Path.Combine(path, "src", "main", "AndroidManifest.xml");
            var x = new XmlDocument(); x.Load(f);
            var man = x.DocumentElement;
            string pkg = PlayerSettings.GetApplicationIdentifier(NamedBuildTarget.Android);

            if (!x.OuterXml.Contains("android.permission.REQUEST_INSTALL_PACKAGES"))
            {
                var perm = x.CreateElement("uses-permission");
                A(x, perm, "name", "android.permission.REQUEST_INSTALL_PACKAGES");
                man.InsertBefore(perm, man.FirstChild);
            }
            var app = man["application"];
            if (app == null) { app = x.CreateElement("application"); man.AppendChild(app); }
            if (!x.OuterXml.Contains("com.routedefense.RDInstall"))
            {
                var prov = x.CreateElement("provider");
                A(x, prov, "name", "com.routedefense.RDInstall");
                A(x, prov, "authorities", pkg + ".rdapk");
                A(x, prov, "exported", "false");
                A(x, prov, "grantUriPermissions", "true");
                app.AppendChild(prov);
            }
            x.Save(f);
        }
        // android:-prefixed attribute, written with the android: prefix whether or not the element is in the tree yet
        static void A(XmlDocument x, XmlElement e, string name, string value) { var a = x.CreateAttribute("android", name, NS); a.Value = value; e.Attributes.Append(a); }
    }
}
