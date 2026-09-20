package com.jmewing.taptosay

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.PersistableBundle
import android.util.Log
import java.io.File
import java.io.FileWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Persistent, shell-readable instrumentation for diagnosing device-owner
 * provisioning. The app is a release (non-debuggable) device-owner build, so
 * `run-as` can't read its data dir; writing to external app storage
 * (/sdcard/Android/data/com.jmewing.taptosay/files/provisioning.log) lets an
 * ADB shell read it after a factory reset without root.
 *
 * Goal: decide whether Android/clouddpc EVER delivers the QR admin-extras to
 * TapToSay, and through what intent/component — so we fix the right path.
 */
object ProvisioningLog {
    private const val TAG = "TapToSayProv"
    private val fmt = SimpleDateFormat("yyyy-MM-dd HH:mm:ss.SSS", Locale.US)

    /** Flatten an arbitrary value for logging; expands Bundle/PersistableBundle. */
    fun flattenAny(v: Any?): String {
        if (v is PersistableBundle) {
            return "{" + v.keySet().joinToString(",") { k -> "$k=${v.get(k)}" } + "}"
        }
        if (v is Bundle) {
            return "{" + v.keySet().joinToString(",") { k -> "$k=${v.get(k)}" } + "}"
        }
        return v?.toString() ?: "null"
    }

    /** One-line description of an intent's action/component/extras. */
    fun describeIntent(intent: Intent?): String {
        if (intent == null) return "null"
        val b = StringBuilder()
        b.append("action=").append(intent.action)
            .append(" comp=").append(intent.component)
        val extras = intent.extras
        if (extras != null) {
            b.append(" extras{")
            var first = true
            for (k in extras.keySet()) {
                if (!first) b.append(", ")
                first = false
                b.append(k).append('=').append(flattenAny(extras.get(k)))
            }
            b.append("}")
        } else {
            b.append(" noExtras")
        }
        return b.toString()
    }

    /** Write the admin-extras bundle to a JSON file in external app storage,
     *  readable by the app on first launch as well as by an ADB shell.
     *  Returns the file path written, or null on failure. */
    @Synchronized
    fun writeExtrasFile(context: Context, extras: PersistableBundle): File? {
        return try {
            val dir = context.getExternalFilesDir(null) ?: context.filesDir
            val f = File(dir, "admin_extras.json")
            val map = LinkedHashMap<String, String>()
            for (k in extras.keySet()) {
                extras.getString(k)?.let { map[k] = it }
            }
            val json = org.json.JSONObject(map).toString()
            FileWriter(f, false).use { it.append(json) }
            f
        } catch (_: Exception) {
            null
        }
    }

    /** Read the admin-extras file written during provisioning, if present. */
    fun readExtrasFile(context: Context): Map<String, String> {
        return try {
            val dir = context.getExternalFilesDir(null) ?: context.filesDir
            val f = File(dir, "admin_extras.json")
            if (!f.exists()) return emptyMap()
            val text = f.readText()
            val obj = org.json.JSONObject(text)
            obj.keys().asSequence().associateWith { obj.optString(it) }
        } catch (_: Exception) {
            emptyMap()
        }
    }

    /** Append a timestamped line to logcat AND the persistent on-disk log. */
    @Synchronized
    fun record(context: Context, tag: String, message: String) {
        val line = "[${fmt.format(Date())}] $tag: $message"
        Log.i(TAG, line)
        try {
            val dir = context.getExternalFilesDir(null) ?: context.filesDir
            val f = File(dir, "provisioning.log")
            FileWriter(f, true).use { it.append(line).append('\n') }
        } catch (_: Exception) {
            // non-fatal — logging must never crash provisioning
        }
    }
}
