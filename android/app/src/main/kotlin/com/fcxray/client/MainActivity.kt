package com.fcxray.client

import android.app.Activity
import android.content.Intent
import android.net.VpnService
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
        MethodChannel(engine.dartExecutor.binaryMessenger, "com.fcxray.client/documents")
            .setMethodCallHandler { call, result ->
                if (call.method != "saveRules") {
                    result.notImplemented()
                } else if (exportReply != null) {
                    result.error("BUSY", "A save dialog is open", null)
                } else {
                    val bytes = call.arguments as? ByteArray
                    if (bytes == null || bytes.size > 1024 * 1024) {
                        result.error("SIZE", "Invalid rule file", null)
                    } else {
                        exportReply = result
                        exportBytes = bytes
                        try {
                            startActivityForResult(Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                                putExtra(Intent.EXTRA_TITLE, "fcxray-rules.json")
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
                        val permission = VpnService.prepare(this)
                        if (permission == null) startVpn() else startActivityForResult(permission, 1001)
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
        if (resultCode == Activity.RESULT_OK) startVpn() else {
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
