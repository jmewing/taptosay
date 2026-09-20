package com.jmewing.taptosay

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

class TapToSayDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        const val PREFS_NAME = "taptosay_provisioning"
        val EXTRAS_KEYS = arrayOf(
            "server_url", "student_id", "school_tea_id",
            "auth_password", "tablet_id", "enrollment_token",
        )
    }

    // Instrument every provisioning-related (or admin) intent this receiver
    // legitimately receives, persistently, so we can see after a factory reset
    // whether Android/clouddpc ever delivered the QR extras and via what path.
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: ""
        if (action.startsWith("android.app.action.PROVISIONING") ||
            action == "android.app.action.DEVICE_ADMIN_ENABLED" ||
            action == "android.app.action.PROVISIONING_SUCCESSFUL" ||
            action == "android.app.action.PROFILE_PROVISIONING_COMPLETE" ||
            action.startsWith("android.app.action.ACTION") ||
            action.contains("PROVISIONING")
        ) {
            ProvisioningLog.record(
                context, "RECEIVER",
                "onReceive action=${ProvisioningLog.describeIntent(intent)}"
            )
        }
        super.onReceive(context, intent)
    }
}
