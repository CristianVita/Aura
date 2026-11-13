package com.example.symphonium_clone

import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.PackageManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import android.util.Log

object BackgroundDownloadBridge {
    private const val CHANNEL = "com.example.symphonium_clone/background_downloads"
    const val PERMISSION = 4290
    private var channel: MethodChannel? = null
    private var permissionPending: MethodChannel.Result? = null
    private var pending: MethodChannel.Result? = null
    private var pendingArgs: Map<String, Any?>? = null
    private var activity: WeakReference<Activity>? = null
    var service: BackgroundDownloadService? = null
    private var intentionalStop = false
    private fun trace(event: String) {
        if (activity?.get()?.packageName?.endsWith(".integration") == true) Log.i("AuraSyntheticService", event)
    }

    fun attach(host: Activity, engine: FlutterEngine) {
        activity = WeakReference(host)
        trace("bridge-attached")
        val appContext = host.applicationContext
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "permission" -> {
                        trace("permission-request")
                        val current = activity?.get()
                        if (current == null || current.isFinishing) result.error("unavailable", "Activity unavailable", null)
                        else if (Build.VERSION.SDK_INT < 33 || current.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) result.success(true)
                        else if (permissionPending != null) result.error("busy", "Permission request already active", null)
                        else { permissionPending = result; current.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), PERMISSION) }
                    }
                    "start" -> {
                        trace("start-request")
                        if (pending != null || service != null) result.error("busy", "A background transfer is already active", null)
                        else {
                            @Suppress("UNCHECKED_CAST")
                            val args = call.arguments as? Map<String, Any?>
                            val current = activity?.get()
                            if (args == null) result.error("invalid", "Missing notification data", null)
                            else if (current == null || current.isFinishing) result.error("unavailable", "Activity unavailable", null)
                            else if (Build.VERSION.SDK_INT >= 33 && current.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) result.error("notification_denied", "Notification permission is required", null)
                            else { pending = result; pendingArgs = args; launch(current) }
                        }
                    }
                    "update" -> {
                        val active = service
                        if (active == null) result.error("unavailable", "Transfer service stopped", null)
                        else { active.update(call.argument<Int>("done") ?: 0, call.argument<Int>("total") ?: 0); result.success(null) }
                    }
                    "stop" -> {
                        val active = pending != null || service != null
                        if (pending != null) fail("cancelled", "Transfer start cancelled")
                        intentionalStop = active
                        if (!appContext.stopService(Intent(appContext, BackgroundDownloadService::class.java))) intentionalStop = false
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
    fun permissionResult(granted: Boolean) {
        trace(if (granted) "permission-allowed" else "permission-denied")
        permissionPending?.success(granted)
        permissionPending = null
    }
    private fun launch(host: Activity) {
        val args = pendingArgs ?: return
        try {
            intentionalStop = false
            val intent = Intent(host.applicationContext, BackgroundDownloadService::class.java).setAction(BackgroundDownloadService.START)
                .putExtra("title", args["title"] as? String ?: "Aura")
                .putExtra("progress", args["progress"] as? String ?: "Progress")
                .putExtra("stop", args["stop"] as? String ?: "Stop")
                .putExtra("done", args["done"] as? Int ?: 0)
                .putExtra("total", args["total"] as? Int ?: 0)
            ContextCompat.startForegroundService(host.applicationContext, intent)
        } catch (_: Exception) { fail("start_failed", "Could not start transfer service") }
    }
    fun awaitingStart(): Boolean = pending != null
    fun ready(active: BackgroundDownloadService) {
        trace("audio-bound")
        service = active
        pending?.success(null); pending = null; pendingArgs = null
    }
    fun fail(code: String, message: String) {
        trace("service-failed: $code")
        pending?.error(code, message, null); pending = null; pendingArgs = null
    }
    fun cancel() { channel?.invokeMethod("cancel", null) }
    fun destroyed(active: BackgroundDownloadService) {
        trace("service-destroyed")
        if (service === active) service = null
        if (pending != null) fail("start_failed", "Transfer service stopped")
        else if (!intentionalStop) channel?.invokeMethod("stopped", null)
        intentionalStop = false
    }
}

class BackgroundDownloadService : Service() {
    companion object {
        const val START = "com.example.symphonium_clone.download.START"
        const val CANCEL = "com.example.symphonium_clone.download.CANCEL"
        private const val CHANNEL_ID = "aura_downloads_v1"
        private const val NOTIFICATION_ID = 42890
    }
    private var title = "Aura"
    private var progress = "Progress"
    private var stopLabel = "Stop"
    private var done = 0
    private var total = 0
    private var bound = false
    private var wakeLock: PowerManager.WakeLock? = null
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) { BackgroundDownloadBridge.ready(this@BackgroundDownloadService) }
        override fun onServiceDisconnected(name: ComponentName?) { BackgroundDownloadBridge.cancel(); stopSelf() }
        override fun onBindingDied(name: ComponentName?) { BackgroundDownloadBridge.cancel(); stopSelf() }
        override fun onNullBinding(name: ComponentName?) { BackgroundDownloadBridge.fail("bind_failed", "Audio engine unavailable"); stopSelf() }
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == CANCEL) { BackgroundDownloadBridge.cancel(); return START_NOT_STICKY }
        if (intent?.action != START || !BackgroundDownloadBridge.awaitingStart()) { stopSelf(); return START_NOT_STICKY }
        title = intent.getStringExtra("title") ?: "Aura"
        progress = intent.getStringExtra("progress") ?: "Progress"
        stopLabel = intent.getStringExtra("stop") ?: "Stop"
        done = intent.getIntExtra("done", 0); total = intent.getIntExtra("total", 0)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(CHANNEL_ID, title, NotificationManager.IMPORTANCE_LOW))
            }
            if (packageName.endsWith(".integration")) Log.i("AuraSyntheticService", "foreground-start")
            startForeground(NOTIFICATION_ID, notification())
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Aura:background-download").apply {
                setReferenceCounted(false)
                acquire(6L * 60 * 60 * 1000)
            }
            val audioIntent = Intent(this, AudioService::class.java).setAction("android.media.browse.MediaBrowserService")
            bound = bindService(audioIntent, connection, Context.BIND_AUTO_CREATE)
            if (packageName.endsWith(".integration")) Log.i("AuraSyntheticService", "bind-requested: $bound")
            if (!bound) { BackgroundDownloadBridge.fail("bind_failed", "Audio engine unavailable"); stopSelf() }
        } catch (_: Exception) { BackgroundDownloadBridge.fail("start_failed", "Could not start transfer service"); stopSelf() }
        return START_NOT_STICKY
    }
    private fun notification(): Notification {
        val cancelIntent = Intent(this, BackgroundDownloadService::class.java).setAction(CANCEL)
        val cancel = PendingIntent.getService(this, 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val launch = packageManager.getLaunchIntentForPackage(packageName)
        val open = launch?.let { PendingIntent.getActivity(this, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(com.example.symphonium_clone.R.drawable.ic_stat_audio)
            .setContentTitle(title).setContentText("$progress: $done / $total")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true)
            .setProgress(total, done, total <= 0)
            .addAction(0, stopLabel, cancel).build()
    }
    fun update(value: Int, count: Int) {
        done = value; total = count
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification())
    }
    override fun onTimeout(startId: Int, fgsType: Int) { BackgroundDownloadBridge.cancel(); stopSelf() }
    override fun onDestroy() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
        if (bound) { unbindService(connection); bound = false }
        BackgroundDownloadBridge.destroyed(this)
        super.onDestroy()
    }
}
