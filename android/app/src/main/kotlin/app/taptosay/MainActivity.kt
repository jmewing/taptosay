package app.taptosay

import android.app.PendingIntent
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PersistableBundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        // Explicit broadcast action carrying the result of a PackageInstaller
        // session commit (silent self-update).
        const val ACTION_INSTALL_STATUS = "app.taptosay.INSTALL_STATUS"
    }

    private lateinit var dpm: DevicePolicyManager
    private lateinit var admin: ComponentName
    private var kioskInitialized = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        admin = ComponentName(this, TapToSayDeviceAdminReceiver::class.java)
        ProvisioningLog.record(this, "ACTIVITY", "onCreate intent=${ProvisioningLog.describeIntent(intent)}")
        initKiosk()
        captureProvisioningExtras(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        ProvisioningLog.record(this, "ACTIVITY", "onNewIntent intent=${ProvisioningLog.describeIntent(intent)}")
        captureProvisioningExtras(intent)
    }

    override fun onResume() {
        super.onResume()
        ProvisioningLog.record(this, "ACTIVITY", "onResume (isDeviceOwner=${dpm.isDeviceOwnerApp(packageName)})")
        // Device owner can be granted AFTER first launch, and lock-task must be
        // engaged while the activity is RESUMED (calling it in onCreate throws).
        initKiosk()
        // Attempt to pin the app to the foreground on EVERY resume:
        //  - school/device-owner tablet -> hard kiosk lock (as before)
        //  - BYOD tablet (no device owner)   -> Android screen pinning, i.e.
        //    Guided-Access-style foreground hold; requires "Screen pinning"
        //    enabled in Settings and may prompt once, so it is best-effort.
        try {
            startLockTask()
        } catch (_: Exception) {
            // not allowed (screen pinning off) or not foreground — non-fatal
        }
    }

    /**
     * Device-owner QR/NFC provisioning delivers the admin-extras bundle on the
     * ACTION_PROVISIONING_SUCCESSFUL intent (Android 8+). Persist them to a
     * shared prefs file the Flutter side can read via the kiosk channel.
     */
    private fun captureProvisioningExtras(intent: Intent?) {
        if (intent == null) {
            ProvisioningLog.record(this, "CAPTURE", "captureProvisioningExtras: null intent")
            return
        }
        val extras = intent.getParcelableExtra(
            DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE
        ) as? PersistableBundle
        if (extras == null) {
            ProvisioningLog.record(this, "CAPTURE", "no ADMIN_EXTRAS_BUNDLE on intent; action=${intent.action}")
            return
        }
        ProvisioningLog.record(this, "CAPTURE", "found ADMIN_EXTRAS_BUNDLE: ${ProvisioningLog.flattenAny(extras)}")
        val prefs = getSharedPreferences(TapToSayDeviceAdminReceiver.PREFS_NAME, Context.MODE_PRIVATE)
        val editor = prefs.edit()
        for (key in TapToSayDeviceAdminReceiver.EXTRAS_KEYS) {
            extras.getString(key)?.let { editor.putString(key, it) }
        }
        editor.apply()
    }

    private fun initKiosk() {
        if (kioskInitialized) return
        if (!dpm.isDeviceOwnerApp(packageName)) return
        try {
            dpm.setLockTaskPackages(admin, arrayOf(packageName))
            kioskInitialized = true
        } catch (_: Exception) {
            // non-fatal — retry on next resume
        }
        try {
            val homeFilter = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            dpm.addPersistentPreferredActivity(
                admin,
                homeFilter,
                ComponentName(this, MainActivity::class.java)
            )
        } catch (_: Exception) {
            // non-fatal
        }
        try {
            dpm.setKeyguardDisabled(admin, true)
        } catch (_: Exception) {
            // non-fatal
        }
    }

    /**
     * Install a downloaded APK.
     *
     * Preferred path — when we are the DEVICE OWNER: a PackageInstaller SESSION.
     * AOSP waives the user-action requirement for a device owner
     * (PackageInstallerSession.isInstallerDeviceOwnerOrAffiliatedProfileOwner),
     * so this installs with NO "unknown sources" prompt and without disturbing
     * the kiosk lock. This is the branch that makes an enrolled tablet update
     * itself silently.
     *
     * Fallback path — BYOD / Guided-Access (not device owner), or if the session
     * path fails for any reason: hand the APK to the SYSTEM installer via
     * ACTION_VIEW. On first use Android asks the user to allow installs from
     * this source; that grant persists on later updates.
     */
    private fun installApk(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        if (dpm.isDeviceOwnerApp(packageName) && installViaSession(file)) {
            return true
        }
        return launchSystemInstaller(file)
    }

    /**
     * Silent self-update via a PackageInstaller session. Returns false on any
     * failure so the caller can fall back to the visible installer.
     */
    private fun installViaSession(file: File): Boolean {
        var sessionId = -1
        return try {
            val pi = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            if (Build.VERSION.SDK_INT >= 31) {
                // Ask the platform NOT to require user confirmation. For a
                // device-owner installer AOSP then performs the install
                // silently. On older APIs the flag does not exist, so we skip
                // it and the device-owner exemption still applies.
                params.setRequireUserAction(
                    PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED
                )
            }
            sessionId = pi.createSession(params)
            pi.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("base.apk", 0, file.length()).use { out ->
                        input.copyTo(out)
                        session.fsync(out)
                    }
                }
                val intent = Intent(this, UpdateInstallReceiver::class.java).apply {
                    action = ACTION_INSTALL_STATUS + sessionId
                }
                val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                val pending = PendingIntent.getBroadcast(this, sessionId, intent, flags)
                session.commit(pending.intentSender)
            }
            true
        } catch (e: Exception) {
            ProvisioningLog.record(this, "INSTALL", "session install failed: ${e.message}")
            if (sessionId != -1) {
                try {
                    packageManager.packageInstaller.abandonSession(sessionId)
                } catch (_: Exception) {
                    // best-effort cleanup
                }
            }
            false
        }
    }

    /** Show the system installer UI (the pre-existing behaviour). */
    private fun launchSystemInstaller(file: File): Boolean {
        return try {
            // A device-owner kiosk (lock task) would block the system installer
            // UI. Release the lock so the confirm prompt is usable; onResume
            // re-engages it after the update installs/restarts the app.
            try {
                stopLockTask()
            } catch (_: Exception) {
                // not in lock task — fine
            }
            val uri: Uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.taptosay/kiosk")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "stopLockTask" -> {
                        try {
                            stopLockTask()
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "goHome" -> {
                        try {
                            // TapToSay is the persistent HOME, so a generic HOME
                            // intent loops back here. Resolve the REAL launcher the
                            // device shipped with (could be Samsung, BLU, etc.) and
                            // launch it explicitly so the adult can use the tablet.
                            val homeIntent = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                            }
                            val launcher = packageManager.queryIntentActivities(
                                homeIntent,
                                0
                            )
                                .map { it.activityInfo }        // ResolveInfo -> ActivityInfo
                                .firstOrNull { it.packageName != packageName } // skip TapToSay
                            if (launcher != null) {
                                val target = Intent(Intent.ACTION_MAIN).apply {
                                    addCategory(Intent.CATEGORY_HOME)
                                    component = ComponentName(launcher.packageName, launcher.name)
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(target)
                            }
                            result.success(launcher != null)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "startLockTask" -> {
                        try {
                            startLockTask()
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "getProvisioningExtras" -> {
                        // Extras are captured (from the GET_PROVISIONING_MODE
                        // intent) into external app storage during provisioning;
                        // read that back so first launch auto-provisions.
                        val out = HashMap<String, String>()
                        out.putAll(ProvisioningLog.readExtrasFile(this))
                        result.success(out)
                    }
                    "getAppVersion" -> {
                        try {
                            val info = packageManager.getPackageInfo(packageName, 0)
                            val code = if (Build.VERSION.SDK_INT >= 28) {
                                info.longVersionCode
                            } else {
                                @Suppress("DEPRECATION") info.versionCode.toLong()
                            }
                            val out = HashMap<String, Any>()
                            out["versionCode"] = code.toInt()
                            out["versionName"] = info.versionName ?: ""
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("version", e.message, null)
                        }
                    }
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        result.success(path != null && installApk(path))
                    }
                    "openUrl" -> {
                        // Open a URL with the OS (e.g. the App Store listing). The
                        // iOS-only update nudge calls this; Android keeps its own
                        // APK self-update path, so this is rarely hit here but must
                        // exist so the shared channel never errors.
                        val url = call.argument<String>("url")
                        if (url == null) {
                            result.success(false)
                        } else {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
