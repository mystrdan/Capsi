package win.capsi.app

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

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

        /** Name the Wi-Fi stack shows against Capsi's multicast lock. */
        private const val MULTICAST_LOCK_TAG = "capsi-discovery"
    }

    /** Mirrors the in-app preference so the Dart side does not resend it. */
    private var notificationsEnabled = true

    /**
     * The Wi-Fi multicast lock, held from `onCreate` until `onDestroy`.
     *
     * It is what lets the Rust discovery socket receive the broadcast beacons
     * its peers send, and it lives with the activity because the lock is only
     * worth holding while Capsi is running.
     */
    private var multicastLock: WifiManager.MulticastLock? = null

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
                    "openFile" -> {
                        result.success(openReceivedFile(call))
                    }
                    "revealFile" -> {
                        // Android has no equivalent of "show in folder": the
                        // app's sandbox is not browsable by the user, so this is
                        // reported rather than answered with something misleading.
                        result.success(false)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Hand a received file to whatever app the user has chosen for its type.
     *
     * Received files live in the app's private sandbox, and Android has refused
     * `file://` URIs across process boundaries since API 24 (FileUriExposed), so
     * the only correct route is a content:// URI from a FileProvider, paired with
     * a MIME type resolved from the extension.
     *
     * A read grant is attached to the intent, so the receiving app may read the
     * file for as long as it holds the intent — without it the target app sees a
     * URI it has no permission to open and refuses.
     *
     * Returns false rather than throwing when no app can handle the type, which
     * is an ordinary outcome: an APK on a device with no file viewer installed
     * is still a working Capsi device.
     */
    private fun openReceivedFile(call: MethodCall): Boolean {
        val path = call.argument<String>("path") ?: return false
        val file = File(path)
        if (!file.isFile) return false

        val mime = mimeTypeFor(file.name)
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (_: IllegalArgumentException) {
            // The provider's configured paths do not cover this file.
            return false
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mime)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        // Checked before launching: a type with no installed handler is an
        // ordinary situation, not a crash, and Android 11+ package visibility
        // means resolveActivity can legitimately answer null.
        if (intent.resolveActivity(packageManager) == null) return false

        return try {
            startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        }
    }

    /**
     * The MIME type for [name], derived from its extension.
     *
     * The transfer protocol carries no MIME type, so this is a small local table
     * rather than a guess. Anything unrecognised becomes `application/octet-stream`
     * or `* / *`, which still lets a generic file manager or installer offer to
     * handle it instead of Capsi refusing outright.
     */
    private fun mimeTypeFor(name: String): String {
        val extension = name.substringAfterLast('.', "").lowercase()
        if (extension.isEmpty()) return "*/*"
        return when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "png" -> "image/png"
            "gif" -> "image/gif"
            "webp" -> "image/webp"
            "bmp" -> "image/bmp"
            "heic", "heif" -> "image/heic"
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "3gp" -> "video/3gpp"
            "mp3" -> "audio/mpeg"
            "wav" -> "audio/wav"
            "m4a" -> "audio/mp4"
            "flac" -> "audio/flac"
            "ogg", "oga", "opus" -> "audio/ogg"
            "pdf" -> "application/pdf"
            "zip" -> "application/zip"
            "gz" -> "application/gzip"
            "doc" -> "application/msword"
            "docx" ->
                "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            "xls" -> "application/vnd.ms-excel"
            "xlsx" -> "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            "ppt" -> "application/vnd.ms-powerpoint"
            "pptx" ->
                "application/vnd.openxmlformats-officedocument.presentationml.presentation"
            "txt", "log" -> "text/plain"
            "md" -> "text/markdown"
            "csv" -> "text/csv"
            "json" -> "application/json"
            "xml" -> "text/xml"
            else -> "*/*"
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
        acquireDiscoveryLock()
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
        releaseDiscoveryLock()
        stopMessageListener()
        super.onDestroy()
    }

    /**
     * Ask the Wi-Fi stack to hand Capsi the broadcast datagrams it filters out.
     *
     * Android's Wi-Fi driver drops packets that are not addressed to this device
     * unless a multicast lock is held, and Capsi's peer discovery is a UDP
     * broadcast. Without this the phone never hears a peer announce itself - and
     * is never heard in return, because it is not the only side that filters -
     * while the rest of the app looks perfectly healthy. The lock is set to not
     * reference count because it is taken once for the whole activity lifetime,
     * so the single release in `onDestroy` always matches it.
     *
     * Best effort by design: `createMulticastLock` throws when
     * `CHANGE_WIFI_MULTICAST_STATE` has not been granted, and a build like that
     * carries on in the foreground instead of failing at startup.
     */
    private fun acquireDiscoveryLock() {
        if (multicastLock != null) return
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            ?: return
        try {
            val lock = wifi.createMulticastLock(MULTICAST_LOCK_TAG)
            lock.setReferenceCounted(false)
            lock.acquire()
            multicastLock = lock
        } catch (_: RuntimeException) {
            // No multicast permission, or no Wi-Fi on this build. Discovery
            // still works wherever the platform delivers broadcasts anyway.
            multicastLock = null
        }
    }

    /** Give the multicast lock back. Safe to call when it was never taken. */
    private fun releaseDiscoveryLock() {
        try {
            multicastLock?.release()
        } catch (_: RuntimeException) {
            // The platform already dropped it; there is nothing left to undo.
        }
        multicastLock = null
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
