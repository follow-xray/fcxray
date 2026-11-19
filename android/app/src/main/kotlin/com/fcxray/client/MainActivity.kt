package com.fcxray.client

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var pending: MethodChannel.Result? = null
    private var config: String? = null
    private var assetDirectory: String = ""
    private var exportReply: MethodChannel.Result? = null
    private var exportBytes: ByteArray? = null
    private val handler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "com.fcxray.client/preferences",
            io.flutter.plugin.common.StandardMethodCodec.INSTANCE, messenger.makeBackgroundTaskQueue())
            .setMethodCallHandler { call, result ->
                if (call.method != "flush") {
                    result.notImplemented()
                } else {
                    // flutter_secure_storage 11 uses apply() for these default
                    // stores. A commit on the same preferences waits for pending
                    // writes, including first-use key material, off the UI thread.
                    val stores = if (call.arguments == true) listOf("FlutterSecureKeyStorage:fcxray-backup",
                        "FlutterSecureStorageConfiguration:fcxray-backup", "fcxray-backup") else listOf("FlutterSecureKeyStorage",
                        "FlutterSecureStorageConfiguration:FlutterSecureStorage", "FlutterSecureStorage")
                    try {
                        val saved = stores.all {
                            applicationContext.getSharedPreferences(it, MODE_PRIVATE).edit().commit()
                        }
                        if (saved) result.success(null) else result.error("STORAGE", "Unable to flush saved settings", null)
                    } catch (e: RuntimeException) {
                        result.error("STORAGE", "Unable to flush saved settings", null)
                    }
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.fcxray.client/documents")
            .setMethodCallHandler { call, result ->
                val backup = call.method == "saveBackup"
                if (!backup && call.method != "saveRules") {
                    result.notImplemented()
                } else if (exportReply != null) {
                    result.error("BUSY", "A save dialog is open", null)
                } else {
                    val bytes = call.arguments as? ByteArray
                    val limit = if (backup) 32 * 1024 * 1024 else 1024 * 1024
                    if (bytes == null || bytes.size > limit) {
                        result.error("SIZE", "Invalid JSON document", null)
                    } else {
                        exportReply = result
                        exportBytes = bytes
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, if (backup) "fcxray-backup.json" else "fcxray-rules.json")
                            }, 1002)
                        } catch (e: Exception) {
                            exportReply = null; exportBytes = null
                            result.error("EXPORT", e.message, null)
                        }
                    }
                }
            }
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.fcxray.client/core")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "latency" -> LatencyRequest(applicationContext, call.argument<String>("outbound") ?: "", result).run()
                    "start" -> {
                        if (pending != null) { result.error("BUSY", "VPN authorization is pending", null); return@setMethodCallHandler }
                        val value = call.argument<String>("config")
                        if (value.isNullOrBlank()) { result.error("CONFIG", "Missing configuration", null); return@setMethodCallHandler }
                        pending = result
                        config = value
                        assetDirectory = call.argument<String>("assetDirectory") ?: ""
                        try {
                            val permission = VpnService.prepare(this)
                            if (permission == null) requestNotificationsAndStart() else startActivityForResult(permission, 1001)
                        } catch (e: RuntimeException) {
                            pending = null; config = null
                            result.error("PERMISSION", e.message ?: "Cannot request VPN authorization", null)
                        }
                    }
                    "stop" -> FcxrayVpnService.stop { value, error ->
                        handler.post { if (error == null) result.success(value) else result.error("STOP", error, null) }
                    }
                    "status" -> FcxrayVpnService.status { value, error ->
                        handler.post { if (error == null) result.success(value) else result.error("CORE", error, null) }
                    }
                    "config", "geo", "validate", "applyRules" -> FcxrayVpnService.inspect(call.method, call.argument<String>("config") ?: "", call.argument<String>("assetDirectory") ?: "") { value, error ->
                        handler.post { if (error == null) result.success(value) else result.error("INSPECT", error, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationsAndStart() {
        if (pending == null) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            val preferences = getSharedPreferences("vpn-permissions", MODE_PRIVATE)
            if (!preferences.getBoolean("notificationsAsked", false)) {
                try {
                    requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1003)
                    preferences.edit().putBoolean("notificationsAsked", true).apply()
                    return
                } catch (_: RuntimeException) {
                    // The notification prompt is optional for starting a foreground VPN.
                }
            }
        }
        startVpn()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1003) startVpn()
    }

    private fun startVpn() {
        val result = pending ?: return
        val value = config ?: return
        pending = null
        config = null
        FcxrayVpnService.start(this, value, assetDirectory) { snapshot, error ->
            handler.post { if (error == null) result.success(snapshot) else result.error("VPN", error, null) }
        }
    }

    @Deprecated("Used for VpnService permission result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 1002) {
            val reply = exportReply ?: return
            val bytes = exportBytes
            val uri = data?.data
            exportReply = null; exportBytes = null
            if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) {
                reply.success(false)
            } else {
                Thread {
                    try {
                        val stream = contentResolver.openOutputStream(uri, "wt") ?: error("Cannot open document")
                        stream.use { it.write(bytes) }
                        handler.post { reply.success(true) }
                    } catch (e: Exception) { handler.post { reply.error("EXPORT", e.message, null) } }
                }.start()
            }
            return
        }
        if (requestCode != 1001) return
        if (resultCode == Activity.RESULT_OK) requestNotificationsAndStart() else {
            pending?.error("PERMISSION", "VPN authorization was declined", null)
            pending = null; config = null
        }
    }

    override fun onDestroy() {
        exportReply?.success(false)
        exportReply = null; exportBytes = null
        pending?.error("CANCELLED", "Activity closed during VPN authorization", null)
        pending = null; config = null
        super.onDestroy()
    }
}
