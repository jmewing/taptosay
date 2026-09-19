package com.jmewing.taptosay

import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
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
        initKiosk()
    }

    override fun onResume() {
        super.onResume()
        // Device owner can be granted AFTER first launch, and lock-task must be
        // engaged while the activity is RESUMED (calling it in onCreate throws).
        initKiosk()
        if (dpm.isDeviceOwnerApp(packageName)) {
            try {
                startLockTask()
            } catch (_: Exception) {
                // non-fatal
            }
        }
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
                            if (dpm.isDeviceOwnerApp(packageName)) startLockTask()
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
