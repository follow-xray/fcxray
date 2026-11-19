package com.fcxray.client

import android.content.*
import android.os.*
import io.flutter.plugin.common.MethodChannel

internal class LatencyRequest(private val context: Context, private val outbound: String,
                              private val result: MethodChannel.Result) : ServiceConnection {
    private val handler = Handler(Looper.getMainLooper())
    private val timeout = Runnable { finish(-1) }
    private var bound = false
    private var done = false

    fun run() {
        try {
            bound = context.bindService(Intent(context, LatencyService::class.java), this, Context.BIND_AUTO_CREATE)
            if (bound) handler.postDelayed(timeout, 20000) else finish(-1)
        } catch (_: Exception) { finish(-1) }
    }
    override fun onServiceConnected(name: ComponentName, binder: IBinder) {
        if (done) return
        val reply = Messenger(Handler(Looper.getMainLooper()) { msg -> finish(msg.data.getLong("ms", -1)); true })
        try {
            Messenger(binder).send(Message.obtain().apply {
                replyTo = reply
                data = Bundle().apply { putString("outbound", outbound) }
            })
        } catch (_: Exception) { finish(-1) }
    }
    override fun onServiceDisconnected(name: ComponentName) = finish(-1)
    private fun finish(ms: Long) {
        if (done) return
        done = true
        handler.removeCallbacks(timeout)
        if (bound) context.unbindService(this)
        result.success(ms)
    }
}
