package com.quki.quki_notes

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import android.util.Base64
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import java.io.File
import java.io.IOException
import java.util.UUID

/**
 * Real all-files filesystem I/O for the web app's Capacitor storage backend
 * (project/src/capacitorBackend.ts), plus the all-files-access permission
 * primitives ported from the Flutter app's own
 * android/app/src/main/kotlin/com/quki/quki_notes/StoragePlugin.kt (method
 * bodies for isExternalStorageManager/getExternalDocumentsPath/
 * requestAllFilesAccess are unchanged from that source, translated from a
 * Flutter MethodChannel handler to Capacitor's plugin-call model).
 *
 * Every read/write method here takes an already-resolved absolute path -
 * path resolution and the "stays inside the QuKi folder" containment check
 * both happen once, in TypeScript (CapacitorFsBackend.resolvePath), not
 * here. That keeps this plugin a thin, easily-verified file I/O surface
 * with no path-joining logic of its own to get wrong twice.
 *
 * Deliberately plain java.io.File I/O, not @capacitor/filesystem's built-in
 * scoped-storage APIs - that plugin's model is more restrictive than the
 * real all-files access this app already has approved and would not
 * preserve the ported behavior.
 *
 * Also hosts the Flutter-to-Capacitor migration primitives
 * (getFlutterMigrationInfo/isValidWritableDirectory, near the bottom) - real
 * Android Context/File API calls that project/src/androidFlutterMigration.ts
 * has no other way to reach from inside a WebView.
 */
@CapacitorPlugin(name = "Storage")
class StoragePlugin : Plugin() {

    @PluginMethod
    fun readText(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        try {
            val ret = JSObject()
            ret.put("content", File(path).readText(Charsets.UTF_8))
            call.resolve(ret)
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun writeTextAtomic(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val content = call.getString("content") ?: return call.reject("content is required")
        try {
            writeAtomic(path) { it.writeText(content, Charsets.UTF_8) }
            call.resolve()
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun readBinary(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        try {
            val ret = JSObject()
            ret.put("data", Base64.encodeToString(File(path).readBytes(), Base64.NO_WRAP))
            call.resolve(ret)
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun writeBinaryAtomic(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val data = call.getString("data") ?: return call.reject("data is required")
        try {
            val bytes = Base64.decode(data, Base64.NO_WRAP)
            writeAtomic(path) { it.writeBytes(bytes) }
            call.resolve()
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun remove(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        try {
            val file = File(path)
            if (file.exists() && !file.delete()) throw IOException("delete failed: $path")
            call.resolve()
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun rename(call: PluginCall) {
        val from = call.getString("from") ?: return call.reject("from is required")
        val to = call.getString("to") ?: return call.reject("to is required")
        try {
            val dest = File(to)
            dest.parentFile?.mkdirs()
            if (!File(from).renameTo(dest)) throw IOException("rename failed: $from -> $to")
            call.resolve()
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    @PluginMethod
    fun exists(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val ret = JSObject()
        ret.put("exists", File(path).exists())
        call.resolve(ret)
    }

    @PluginMethod
    fun stat(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val file = File(path)
        if (!file.exists()) return call.reject("ENOENT: no such file or directory: $path")
        val ret = JSObject()
        ret.put("size", file.length())
        ret.put("mtimeMs", file.lastModified())
        // java.io.File exposes no creation-time API, and even java.nio.file's
        // BasicFileAttributes.creationTime() (API 26+) is unreliable on
        // Android's common ext4 filesystem, which doesn't track it - so
        // there is no honest birthtime to report here. 0 mirrors
        // OpfsBackend.stat's own fallback (core/src/opfsBackend.ts) for the
        // same reason; QuKiStore already treats a non-positive birthtimeMs
        // as "fall back to mtimeMs" (core/src/quKiStore.ts).
        ret.put("birthtimeMs", 0)
        call.resolve(ret)
    }

    @PluginMethod
    fun listDir(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val file = File(path)
        val entries = if (file.exists()) file.list()?.toList() ?: emptyList() else emptyList()
        val ret = JSObject()
        ret.put("entries", JSArray(entries))
        call.resolve(ret)
    }

    @PluginMethod
    fun mkdirp(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        try {
            val file = File(path)
            if (!file.exists() && !file.mkdirs()) throw IOException("mkdirp failed: $path")
            call.resolve()
        } catch (e: Exception) {
            call.reject(e.message, e)
        }
    }

    // --- All-files-access permission primitives, ported from the Flutter
    // app's android/app/src/main/kotlin/com/quki/quki_notes/StoragePlugin.kt
    // (see this file's class doc comment). Not wired into any onboarding
    // flow yet - that is a later chunk - but exposed now so that chunk can
    // call straight into this plugin without touching the native side again.

    @PluginMethod
    fun isExternalStorageManager(call: PluginCall) {
        val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true // Pre-Android 11 does not need this permission
        }
        val ret = JSObject()
        ret.put("granted", granted)
        call.resolve(ret)
    }

    @PluginMethod
    fun getExternalDocumentsPath(call: PluginCall) {
        val docsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val ret = JSObject()
        ret.put("path", docsDir.absolutePath + "/QuKi_Notes")
        call.resolve(ret)
    }

    /**
     * `context.filesDir.absolutePath` - the app's private internal storage
     * directory, bare and unsuffixed. Callers in TypeScript (androidSetupApi.ts)
     * compose "/QuKi_Notes" (the app-storage choice) or "/quki_settings.json"
     * (the storage-choice settings file) on top of this, matching this
     * plugin's existing philosophy of thin, path-agnostic native I/O -
     * mirrors getExternalDocumentsPath above in only resolving a path, never
     * creating a directory.
     */
    @PluginMethod
    fun getPrivateStoragePath(call: PluginCall) {
        val ret = JSObject()
        ret.put("path", context.filesDir.absolutePath)
        call.resolve(ret)
    }

    @PluginMethod
    fun requestAllFilesAccess(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val intent = Intent(
                Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.parse("package:${context.packageName}"),
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }
        call.resolve()
    }

    // --- Flutter-to-Capacitor migration detection, Android side. Mirrors
    // project/electron/src/flutterMigration.ts's spirit (same STORAGE_CONTRACT.md
    // migration section) against real Android mechanisms instead of a JSON
    // file: the Flutter app's classic `SharedPreferences.getInstance()` reads
    // through shared_preferences_android's LegacySharedPreferencesPlugin
    // (confirmed by reading that plugin's real source in the local pub
    // cache), which calls exactly
    // `context.getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)`
    // - a plain Context API call, not Flutter-specific machinery, so this
    // Kotlin code reads the same file through the same API rather than
    // parsing its on-disk XML directly. The two keys read here
    // ("flutter.storage.location_chosen", "flutter.storage.base_path") are
    // exactly what lib/core/storage/storage_location_service.dart writes,
    // through the classic wrapper's default "flutter." key prefix.

    @PluginMethod
    fun getFlutterMigrationInfo(call: PluginCall) {
        val prefs = context.getSharedPreferences("FlutterSharedPreferences", android.content.Context.MODE_PRIVATE)
        val ret = JSObject()
        ret.put("locationChosen", prefs.getBoolean("flutter.storage.location_chosen", false))
        ret.put("basePath", prefs.getString("flutter.storage.base_path", null))
        // path_provider_android's getApplicationDocumentsPath() (confirmed by
        // reading path_provider_android-2.3.1's real jnigen source) resolves
        // to `context.getDir("flutter", MODE_PRIVATE)`, which Android names
        // "app_flutter" under the app's private data directory. Built here
        // from context.filesDir's parent rather than by calling getDir()
        // itself, so resolving this path never has the side effect of
        // creating that directory if the Flutter app never did.
        val appFlutterDir = File(context.filesDir.parentFile, "app_flutter")
        ret.put("appDocumentsPath", appFlutterDir.absolutePath)
        call.resolve(ret)
    }

    /**
     * Real functional check that a candidate directory is safe to adopt as a
     * migrated storage root - exists, is genuinely a directory, and a real
     * write actually succeeds there. Matches
     * project/electron/src/storageValidation.ts's isValidWritableDirectory
     * exactly in spirit (a permissions-bit check can lie; a real write
     * cannot) - the same reasoning applies on Android, where a directory
     * that exists but sits on now-unmounted/removed storage would otherwise
     * be silently, wrongly adopted.
     */
    @PluginMethod
    fun isValidWritableDirectory(call: PluginCall) {
        val path = call.getString("path") ?: return call.reject("path is required")
        val ret = JSObject()
        ret.put("valid", checkValidWritableDirectory(path))
        call.resolve(ret)
    }

    private fun checkValidWritableDirectory(path: String): Boolean {
        val dir = File(path)
        if (!dir.isDirectory) return false
        val probe = File(dir, ".quki-storage-write-probe-${UUID.randomUUID()}")
        return try {
            probe.writeText("")
            true
        } catch (e: Exception) {
            false
        } finally {
            probe.delete()
        }
    }

    /**
     * Temp-then-rename, matching NodeFsBackend.writeTextAtomic/writeBinaryAtomic
     * (core/src/nodeFsBackend.ts) and, before that, the Flutter app's own
     * _writeAtomic (quki-rewrite-path.md: "the atomic temp-then-rename write
     * carries across"). The rename-retry loop that same source explicitly
     * says not to carry across is not reproduced here.
     */
    private fun writeAtomic(path: String, write: (File) -> Unit) {
        val dest = File(path)
        dest.parentFile?.mkdirs()
        val tmp = File(dest.parentFile, "${dest.name}.${UUID.randomUUID()}.tmp")
        write(tmp)
        if (!tmp.renameTo(dest)) throw IOException("rename failed: ${tmp.path} -> ${dest.path}")
    }
}
