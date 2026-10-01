package win.capsi.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/**
 * Keeps the Capsi process alive while the app is in the background.
 *
 * The message listener is a TCP listener owned by the Rust bridge, and that
 * bridge runs on threads inside this same process: the service deliberately
 * does not set `android:process`, so both share one. Without a foreground
 * service Android may reclaim that process once the app is backgrounded, and the
 * listener goes down with it, so incoming messages, files and workplace syncs
 * quietly stop arriving with nothing in the UI to say so. Holding a foreground
 * notification keeps the process at a priority the platform will not reclaim.
 *
 * The notification is permanent and actionless. It is the visible cost of staying
 * reachable, which is what Android requires and what a user can always see.
 */
class MessageListenerService : Service() {
    companion object {
        const val CHANNEL_ID = "capsi_message_listener"
        const val NOTIFICATION_ID = 1

        @JvmStatic
        fun intent(context: android.content.Context): Intent =
            Intent(context, MessageListenerService::class.java)
    }

    override fun onCreate() {
        super.onCreate()
        startForeground(NOTIFICATION_ID, buildNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // START_STICKY so that if the process is reclaimed under memory pressure
        // Android brings the service back rather than dropping it for good. The
        // Dart side reattaches the listener on its next resume.
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun buildNotification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        // The channel has to exist before the notification is posted on API 26+,
        // and re-creating it on every start is harmless (it is idempotent).
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Capsi message listener",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Keeps Capsi reachable for messages, files and workplace updates."
                setShowBadge(false)
            },
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("Capsi is listening")
            .setContentText("Receiving messages, files and workplace updates.")
            .setOngoing(true)
            .build()
    }
}