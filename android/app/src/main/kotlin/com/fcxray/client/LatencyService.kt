package com.fcxray.client

import android.app.Service
import android.content.Intent
import android.os.*
import bridge.Bridge
import java.util.concurrent.Executors

// Separate process: Xray's package globals, loggers and TUN state belong to
// the process. A serial worker also isolates simultaneous Android batch jobs.
class LatencyService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    private val messenger = Messenger(Handler(Looper.getMainLooper()) { request ->
        val reply = request.replyTo
        val outbound = request.data.getString("outbound") ?: ""
        worker.execute {
            val elapsed = try { Bridge.probe(outbound) } catch (_: Throwable) { -1L }
            val response = Message.obtain().apply {
                data = Bundle().apply { putLong("ms", elapsed) }
            }
            try { reply.send(response) } catch (_: RemoteException) { }
        }
        true
    })
    override fun onBind(intent: Intent) = messenger.binder
    override fun onDestroy() { worker.shutdown(); super.onDestroy() }
}
