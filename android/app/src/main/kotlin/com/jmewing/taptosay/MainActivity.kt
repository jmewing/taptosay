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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
        admin = ComponentName(this, TapToSayDeviceAdminReceiver::class.java)

        if (dpm.isDeviceOwnerApp(packageName)) {
            // Kiosk mode: whitelist lock task + pin this app as the only task.
            // (Device owner is exempt from the lock-task whitelist, so this is belt-and-braces.)
            try {
                dpm.setLockTaskPackages(admin, arrayOf(packageName))
                startLockTask()
            } catch (_: Exception) {
                // non-fatal — still runs; lock just won't engage
            }
            // Boot straight into TapToSay: make it the persistent HOME.
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
            // Bypass the keyguard so boot lands in TapToSay, not the lock screen.
            try {
                dpm.setKeyguardDisabled(admin, true)
            } catch (_: Exception) {
                // non-fatal
            }
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
