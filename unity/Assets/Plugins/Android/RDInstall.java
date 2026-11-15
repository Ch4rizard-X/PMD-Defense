// Route Defense — installs a downloaded update APK.
// The game downloads the new APK to its own files folder as update.apk; this class hands it to Android's installer
// through a private content:// link (Android 7+ refuses plain file paths), so the player only taps "Install".
// The same signing key on both APKs makes Android install over the old app and keep the save.
package com.routedefense;

import android.app.Activity;
import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.database.MatrixCursor;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.provider.OpenableColumns;
import android.provider.Settings;
import java.io.File;
import java.io.FileNotFoundException;

public class RDInstall extends ContentProvider {
    static final String MIME = "application/vnd.android.package-archive";
    static final String NAME = "update.apk";

    // ---- called from the game (C#) ----
    public static long versionCode(Activity a) {
        try {
            android.content.pm.PackageInfo p = a.getPackageManager().getPackageInfo(a.getPackageName(), 0);
            return Build.VERSION.SDK_INT >= 28 ? p.getLongVersionCode() : p.versionCode;
        } catch (Exception e) { return 0; }
    }
    public static boolean canInstall(Activity a) {
        return Build.VERSION.SDK_INT < 26 || a.getPackageManager().canRequestPackageInstalls();
    }
    // Android 8+: the one-time "Allow from this source" switch for this app
    public static void askPermission(Activity a) {
        try { a.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + a.getPackageName()))); }
        catch (Exception e) { a.startActivity(new Intent(Settings.ACTION_SECURITY_SETTINGS)); }
    }
    // returns "" when the installer opened, otherwise the error
    public static String install(Activity a) {
        try {
            Intent i = new Intent(Intent.ACTION_VIEW);
            i.setDataAndType(Uri.parse("content://" + a.getPackageName() + ".rdapk/" + NAME), MIME);
            i.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
            a.startActivity(i);
            return "";
        } catch (Exception e) { return e.toString(); }
    }

    // ---- the private link: serves only update.apk from the game's files folder ----
    File file() {
        Context c = getContext();
        File ext = c.getExternalFilesDir(null);   // Unity's Application.persistentDataPath on most phones
        if (ext != null) { File f = new File(ext, NAME); if (f.exists()) return f; }
        return new File(c.getFilesDir(), NAME);   // persistentDataPath when there is no external storage
    }
    @Override public boolean onCreate() { return true; }
    @Override public String getType(Uri u) { return MIME; }
    @Override public ParcelFileDescriptor openFile(Uri u, String mode) throws FileNotFoundException {
        if (!NAME.equals(u.getLastPathSegment())) throw new FileNotFoundException(u.toString());
        return ParcelFileDescriptor.open(file(), ParcelFileDescriptor.MODE_READ_ONLY);
    }
    @Override public Cursor query(Uri u, String[] proj, String sel, String[] args, String sort) {
        MatrixCursor m = new MatrixCursor(new String[] { OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE });
        m.addRow(new Object[] { "RouteDefense.apk", file().length() });
        return m;
    }
    @Override public Uri insert(Uri u, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri u, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri u, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
}
