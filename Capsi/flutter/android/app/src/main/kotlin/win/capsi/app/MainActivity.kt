package win.capsi.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Capsi's Android host.
 *
 * Beyond hosting the Flutter view, this handles `capsiPlatformChannel` (see
 * lib/main.dart): Flutter cannot raise an Android notification itself, so the
 * Dart layer asks for one here. Only the methods the Dart side actually calls
 * are answered; anything else is reported as unimplemented rather than being
 * silently accepted. It also holds the process in the foreground so the Rust
 * message listener is not reclaimed while Capsi is in the background.
 */
class MainActivity : FlutterActivity() {

    companion object {
        /** Must match `capsiPlatformChannel` in lib/main.dart. */
        private const val PLATFORM_CHANNEL = "win.capsi.app/platform"

        /**
         * Channel for incoming messages, deliberately separate from the
         * always-on "Capsi is listening" one the foreground service uses, so a
         * user can silence messages without stopping the app being reachable.
         */
        private const val MESSAGE_CHANNEL_ID = "capsi_messages"
        private const val MESSAGE_NOTIFICATION_ID = 2

        /** Arbitrary request code for the Android 13+ permission prompt. */
        private const val NOTIFICATION_PERMISSION_REQUEST = 47
    }

    /** Mirrors the in-app preference so the Dart side does not resend it. */
    private var notificationsEnabled = true

    /**
     * Hold the process in the foreground for as long as the app is running.
     *
     * The Rust message listener lives on threads in this process, so once the
     * activity is backgrounded the platform is free to kill the process and take
     * the listener with it. Starting the service keeps the process at foreground
     * priority. It is started from the activity rather than on boot, so Capsi
     * only stays reachable while a user has actually opened it, and it is
     * stopped again on destroy so quitting the app releases the notification.
     */
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PLATFORM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "notify" -> {
                        result.success(postMessageNotification(call))
                    }
                    "setNotificationsEnabled" -> {
                        notificationsEnabled = call.arguments as? Boolean ?: true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun postMessageNotification(call: MethodCall): Boolean {
        if (!notificationsEnabled) return false

        val manager = getSystemService(NotificationManager::class.java)

        // The in-app switch is only half of it: a user can also block
        // notifications for the whole app in system settings, or deny the
        // Android 13+ permission. notify() then drops the notification in
        // silence, so report the failure instead of claiming a notification was
        // shown and leaving the Dart side to assume it worked.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N &&
            !manager.areNotificationsEnabled()
        ) {
            return false
        }

        manager.createNotificationChannel(
            NotificationChannel(
                MESSAGE_CHANNEL_ID,
                "Messages",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply { description = "Notifications for incoming messages and files." },
        )

        val title = call.argument<String>("title") ?: "Capsi"
        val body = call.argument<String>("body").orEmpty()

        // Tapping the notification opens the app rather than doing nothing.
        val launch = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        val pending = launch?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, MESSAGE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        builder.setContentTitle(title)
            .setContentText(body)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setAutoCancel(true)
        pending?.let { builder.setContentIntent(it) }

        manager.notify(MESSAGE_NOTIFICATION_ID, builder.build())
        return true
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermission()
        startMessageListener()
    }

    /**
     * Ask for `POST_NOTIFICATIONS` on Android 13 and later.
     *
     * The permission is declared in the manifest, but from API 33 it is also a
     * runtime permission: without an explicit request the system never prompts
     * and every `notify` call is dropped in silence, which would look to a user
     * like notifications being broken. Below API 33 the permission does not
     * exist, so nothing is asked.
     *
     * The framework's own `checkSelfPermission`/`requestPermissions` are used
     * rather than `ContextCompat`, so this does not pull in an androidx.core
     * dependency just for one prompt. Both are API 23, and the call site below
     * API 33 makes that safe without further guards. The response is not
     * handled: there is nothing to undo on denial, and the next message retries
     * nothing, so the prompt is fire-and-forget by design.
     */
    private fun requestNotificationPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    override fun onDestroy() {
        stopMessageListener()
        super.onDestroy()
    }

    private fun startMessageListener() {
        val service = MessageListenerService.intent(this)
        // Android 8+ refuses a background startForegroundService, but from a
        // visible activity startForegroundService is the correct call: it lets
        // the service promote itself within the five-second window.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                // Context.startForegroundService, used directly so the app does
                // not need an androidx.core dependency just for this call.
                startForegroundService(service)
            } else {
                startService(service)
            }
        } catch (_: SecurityException) {
            // Missing permission on an OEM-restricted build. The app still runs
            // and works while it is in the foreground, which is the same
            // behaviour it had before this service existed.
        }
    }

    private fun stopMessageListener() {
        try {
            stopService(MessageListenerService.intent(this))
        } catch (_: SecurityException) {
            // Nothing to stop if the service never started.
        }
    }
}
