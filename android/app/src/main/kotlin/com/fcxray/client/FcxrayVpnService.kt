package com.fcxray.client

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import bridge.Bridge
import bridge.Protector
import org.json.JSONObject
import java.util.concurrent.Executors

typealias CoreReply = (String?, String?) -> Unit

class FcxrayVpnService : VpnService(), Protector {
    private var tunnel: ParcelFileDescriptor? = null
    @Volatile private var revoked = false

    companion object {
        // One queue owns all Go lifecycle operations and FD disposal.
        private val worker = Executors.newSingleThreadExecutor()
        private val main = Handler(Looper.getMainLooper())
        @Volatile private var current: FcxrayVpnService? = null
        @Volatile private var lastError: String? = null
        private var pendingConfig: String? = null
        private var pendingAssets: String = ""
        private var pendingReply: CoreReply? = null
        private const val STOP = "com.fcxray.client.STOP"

        @Synchronized fun start(context: Context, config: String, assets: String, reply: CoreReply) {
            if (pendingReply != null || current != null) { reply(null, "VPN is already running or starting"); return }
            pendingConfig = config
            pendingAssets = assets
            pendingReply = reply
            try {
                val intent = Intent(context, FcxrayVpnService::class.java)
                if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
            } catch (e: Exception) {
                pendingConfig = null; pendingReply = null; reply(null, e.message)
            }
        }

        fun inspect(method: String, config: String, assets: String, reply: CoreReply) { worker.execute {
            try {
                val result = when (method) {
                    "config" -> Bridge.configuration()
                    "geo" -> { val input = JSONObject(config); Bridge.inspectGeo(input.getString("kind"), input.getString("path")) }
                    "applyRules" -> { Bridge.applyRules(config, assets); Bridge.snapshot() }
                    "validate" -> { Bridge.validateWithAssets(config, assets); Bridge.snapshot() }
                    else -> error("Unknown inspection method")
                }
                reply(result, null)
            } catch (e: Throwable) { reply(null, e.message ?: "Inspection failed") }
        } }

        fun status(reply: CoreReply) { worker.execute {
            try {
                val snapshot = JSONObject(Bridge.snapshot())
                lastError?.let { snapshot.put("error", it) }
                reply(snapshot.toString(), null)
            } catch (e: Throwable) { reply(null, e.message ?: "Core unavailable") }
        } }

        fun stop(reply: CoreReply) { worker.execute {
            try {
                val service = current
                if (service != null) service.cleanup() else Bridge.stop()
                reply(Bridge.snapshot(), null)
            } catch (e: Throwable) { reply(null, e.message ?: "Stop failed") }
        } }
    }

    override fun onCreate() { super.onCreate(); current = this }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP) { stop { _, _ -> }; return START_NOT_STICKY }
        val (config, reply, assets) = synchronized(FcxrayVpnService::class.java) {
            val pair = Triple(pendingConfig, pendingReply, pendingAssets)
            pendingConfig = null; pendingReply = null; pendingAssets = ""; pair
        }
        if (config == null) { stopSelf(); return START_NOT_STICKY }
        try { showNotification() } catch (e: Exception) {
            reply?.invoke(null, e.message ?: "Foreground service failed"); stopSelf(); return START_NOT_STICKY
        }
        worker.execute {
            try {
                lastError = null
                check(!revoked) { "VPN authorization revoked" }
                Bridge.validateWithAssets(config, assets)
                tunnel = Builder().setSession("fcxray").setMtu(1500)
                    .addAddress("172.19.0.1", 30)
                    .addAddress("fdfe:dcba:9876::1", 126)
                    .addRoute("0.0.0.0", 0).addRoute("::", 0)
                    .addDnsServer("1.1.1.1")
                    // Inherit the underlying network's metering on Android 10+.
                    .apply { if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) setMetered(false) }
                    // Covers the Go runtime's own bootstrap DNS sockets too.
                    .addDisallowedApplication(packageName)
                    .establish() ?: error("VPN permission was revoked")
                check(!revoked) { "VPN authorization revoked" }
                Bridge.startWithAssets(config, tunnel!!.fd.toLong(), this, assets)
                reply?.invoke(Bridge.snapshot(), null)
            } catch (e: Throwable) {
                lastError = e.message ?: "VPN startup failed"
                try { cleanup() } catch (_: Throwable) { }
                reply?.invoke(null, lastError)
            }
        }
        return START_NOT_STICKY
    }

    override fun protect(fd: Long): Boolean = protect(fd.toInt())

    private fun showNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
            NotificationChannel("vpn", "VPN connection", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val disconnect = PendingIntent.getService(this, 1, Intent(this, FcxrayVpnService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "vpn") else Notification.Builder(this)
        val notification = builder.setContentTitle("fcxray")
            .setContentText("VPN is running").setSmallIcon(R.drawable.ic_follow_notification)
            .setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Disconnect", disconnect).build()).build()
        if (Build.VERSION.SDK_INT >= 34) startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        else startForeground(1, notification)
    }

    private fun cleanup() {
        // Only this instance may close its core; a delayed onDestroy from an old
        // service must not close a newly created session.
        try { if (current === this) Bridge.stop() } finally {
            tunnel?.close(); tunnel = null
            if (current === this) current = null
            main.post { stopForeground(STOP_FOREGROUND_REMOVE); stopSelf() }
        }
    }

    override fun onRevoke() {
        revoked = true
        worker.execute { try { cleanup() } catch (_: Throwable) { } }
        super.onRevoke()
    }

    override fun onDestroy() {
        revoked = true
        worker.execute { try { cleanup() } catch (_: Throwable) { } }
        super.onDestroy()
    }
}
