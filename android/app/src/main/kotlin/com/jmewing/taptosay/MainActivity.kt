package com.jmewing.taptosay

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.PersistableBundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.jmewing.taptosay/kiosk")
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
                            // intent would loop back here. Launch the Samsung
                            // launcher explicitly so the adult can use the tablet.
                            val launcher = ComponentName(
                                "com.sec.android.app.launcher",
                                "com.sec.android.app.launcher.activities.LauncherActivity"
                            )
                            val home = Intent(Intent.ACTION_MAIN).apply {
                                addCategory(Intent.CATEGORY_HOME)
                                component = launcher
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(home)
                            result.success(true)
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
                    else -> result.notImplemented()
                }
            }
    }
}
