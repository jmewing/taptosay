package com.jmewing.taptosay

import android.app.admin.DeviceAdminReceiver

class TapToSayDeviceAdminReceiver : DeviceAdminReceiver() {

    companion object {
        const val PREFS_NAME = "taptosay_provisioning"
        val EXTRAS_KEYS = arrayOf(
            "server_url", "student_id", "school_tea_id",
            "auth_password", "tablet_id", "enrollment_token",
        )
    }
}
