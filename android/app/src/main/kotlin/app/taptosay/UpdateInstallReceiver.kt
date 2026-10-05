package app.taptosay

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

/**
 * Receives the result of a silent self-update PackageInstaller session.
 *
 * The commit's PendingIntent targets this receiver with a per-session action
 * (see MainActivity.ACTION_INSTALL_STATUS). We only log for diagnostics: a
 * successful silent install replaces this package and restarts the app, so
 * there is usually nothing left to do here.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""
        val label = when (status) {
            PackageInstaller.STATUS_SUCCESS -> "SUCCESS"
            PackageInstaller.STATUS_FAILURE -> "FAILURE"
            PackageInstaller.STATUS_FAILURE_ABORTED -> "ABORTED"
            PackageInstaller.STATUS_FAILURE_BLOCKED -> "BLOCKED"
            PackageInstaller.STATUS_FAILURE_CONFLICT -> "CONFLICT"
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "INCOMPATIBLE"
            PackageInstaller.STATUS_FAILURE_INVALID -> "INVALID"
            PackageInstaller.STATUS_FAILURE_STORAGE -> "STORAGE"
            else -> "UNKNOWN($status)"
        }
        ProvisioningLog.record(
            context, "INSTALL", "session result=$label message=$message"
        )
    }
}
