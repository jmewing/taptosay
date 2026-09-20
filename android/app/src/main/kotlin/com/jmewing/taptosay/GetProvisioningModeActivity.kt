package com.jmewing.taptosay

import android.app.Activity
import android.app.admin.DevicePolicyManager
import android.content.Intent
import android.os.Bundle

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
        val result = Intent().putExtra(
            DevicePolicyManager.EXTRA_PROVISIONING_MODE,
            DevicePolicyManager.PROVISIONING_MODE_FULLY_MANAGED_DEVICE,
        )
        setResult(RESULT_OK, result)
        finish()
    }
}
