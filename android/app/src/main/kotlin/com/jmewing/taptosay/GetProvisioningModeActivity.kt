package com.jmewing.taptosay

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.PersistableBundle

/**
 * Handles the ACTION_GET_PROVISIONING_MODE intent sent during device-owner
 * (QR/NFC) provisioning on newer Android releases (Android 12+ / 16).
 *
 * TapToSay is always a fully-managed device (kiosk), so it answers
 * PROVISIONING_MODE_FULLY_MANAGED_DEVICE immediately. Without this activity the
 * platform can't determine the provisioning mode and aborts with
 * "unable to resolve ACTION_GET_PROVISIONING_MODE" -> "contact your IT admin".
 */
class GetProvisioningModeActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ProvisioningLog.record(
            this, "GET_PROVISIONING_MODE",
            "onCreate intent=${ProvisioningLog.describeIntent(intent)}"
        )
        // The QR/NFC admin-extras are delivered on THIS intent on modern Android
        // (clouddpc): EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE rides the
        // ACTION_GET_PROVISIONING_MODE call. Capture them now so the app can
        // auto-provision on first launch without hand-typing. We persist to
        // external app storage (same mechanism the provisioning.log uses), which
        // was proven writable during provisioning in the 2009 diagnostic build.
        val extras = intent.getParcelableExtra(
            DevicePolicyManager.EXTRA_PROVISIONING_ADMIN_EXTRAS_BUNDLE
        ) as? PersistableBundle
        if (extras != null) {
            ProvisioningLog.writeExtrasFile(this, extras)
            ProvisioningLog.record(
                this, "GET_PROVISIONING_MODE",
                "captured ${TapToSayDeviceAdminReceiver.EXTRAS_KEYS.size} extras to external storage"
            )
        }
        val result = Intent().putExtra(
            DevicePolicyManager.EXTRA_PROVISIONING_MODE,
            DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE,
        )
        setResult(RESULT_OK, result)
        finish()
    }
}
