package com.notifybridge.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.BatteryManager
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import org.json.JSONObject
import java.io.DataInputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.security.SecureRandom
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * Keeps one encrypted connection to the Mac (found over Bonjour) and sends framed AES-GCM JSON.
 * All socket work runs on a single background thread; a 20 s heartbeat keeps the link visible to the Mac
 * and reconnects after Wi-Fi changes.
 */
object Sender {
    private const val SERVICE = "_notifybridge._tcp."
    private const val HEARTBEAT_SECONDS = 45L
    /** Pause before the next reconnect attempt after 0, 1, 2… failures. Keeps battery use low while the Mac is away. */
    private val BACKOFF_MILLIS = longArrayOf(30_000, 60_000, 120_000, 180_000)

    private val io = Executors.newSingleThreadExecutor()
    private val timer = Executors.newSingleThreadScheduledExecutor()
    private val rng = SecureRandom()
    private var socket: Socket? = null
    @Volatile private var nextTry = 0L
    @Volatile private var failures = 0
    private var started = false
    @Volatile private var appCtx: Context? = null

    private fun setLink(state: String) { appCtx?.let { Settings.setLink(it, state) } }

    /** Starts the heartbeat/reconnect loop once. Safe to call from anywhere. */
    fun start(ctx: Context) {
        val app = ctx.applicationContext
        appCtx = app
        synchronized(this) {
            if (started) return
            started = true
        }
        timer.scheduleWithFixedDelay({ io.execute { maintain(app) } }, 1, HEARTBEAT_SECONDS, TimeUnit.SECONDS)

        // Joining a Wi-Fi network: try right away instead of waiting out the backoff. Losing it: drop the dead socket.
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching {
            cm.registerNetworkCallback(
                NetworkRequest.Builder().addTransportType(NetworkCapabilities.TRANSPORT_WIFI).build(),
                object : ConnectivityManager.NetworkCallback() {
                    override fun onAvailable(network: Network) {
                        failures = 0; nextTry = 0
                        io.execute { maintain(app) }
                    }
                    override fun onLost(network: Network) { io.execute { close() } }
                },
            )
        }
    }

    private fun onWifi(ctx: Context): Boolean {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    fun send(ctx: Context, app: String, title: String, text: String) =
        send(ctx, JSONObject().put("type", "post").put("app", app).put("title", title).put("text", text))

    fun sendClip(ctx: Context, text: String) = send(ctx, JSONObject().put("type", "clip").put("text", text))

    fun send(ctx: Context, msg: JSONObject) {
        val appCtx = ctx.applicationContext
        start(appCtx)
        io.execute {
            val key = keyBytes(appCtx)
            if (key == null) {
                Settings.setStatus(appCtx, appCtx.getString(R.string.status_no_key))
                return@execute
            }
            val type = msg.optString("type")
            val queueable = type == "post" && msg.has("id")
            val macAway = (socket?.isClosed ?: true) && System.currentTimeMillis() < nextTry
            if (macAway && (queueable || type == "remove")) {
                // The Mac was unreachable a moment ago: don't spend 12 s retrying for every notification.
                if (queueable) {
                    MissedQueue.add(appCtx, msg)
                    Settings.setStatus(appCtx, appCtx.getString(R.string.queued_waiting, MissedQueue.count(appCtx)))
                } else MissedQueue.remove(appCtx, msg.optString("id"))
                return@execute
            }
            val frame = frame(key, msg.toString())
            for (attempt in 0..1) {
                try {
                    write(connection(appCtx).getOutputStream(), frame)
                    statusFor(appCtx, msg)?.let { Settings.setStatus(appCtx, "$it · ${clock()}") }
                    return@execute
                } catch (e: Exception) {
                    close()
                    if (attempt == 1) {
                        if (queueable) MissedQueue.add(appCtx, msg)
                        if (type == "remove") MissedQueue.remove(appCtx, msg.optString("id"))
                        if (type != "remove") Settings.setStatus(appCtx, appCtx.getString(R.string.status_unreachable))
                    }
                }
            }
        }
    }

    private fun statusFor(ctx: Context, msg: JSONObject): String? = when (msg.optString("type")) {
        "post" -> ctx.getString(R.string.status_sent, msg.optString("app"))
        "clip" -> ctx.getString(R.string.status_clip_sent)
        else -> null
    }

    /** Adds battery level (0-100) and charging state so the Mac can show them. */
    private fun withBattery(ctx: Context, msg: JSONObject): JSONObject {
        val i = ctx.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return msg
        val level = i.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = i.getIntExtra(BatteryManager.EXTRA_SCALE, 100)
        if (level >= 0 && scale > 0) msg.put("battery", level * 100 / scale)
        val status = i.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        msg.put("charging", status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL)
        return msg
    }

    private fun clock() = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())

    private fun keyBytes(ctx: Context): ByteArray? =
        runCatching { Base64.decode(Settings.key(ctx), Base64.DEFAULT) }.getOrNull()?.takeIf { it.size == 32 }

    /** Heartbeat when connected, reconnect (with a pause between tries) when not. */
    private fun maintain(ctx: Context) {
        val key = keyBytes(ctx) ?: return
        val s = socket
        if (s == null || s.isClosed) {
            if (!onWifi(ctx)) { setLink("nowifi"); return }   // never scan on mobile data / without Wi-Fi
            if (System.currentTimeMillis() < nextTry) return
            try {
                connection(ctx)
                failures = 0
                Log.i("NB", "connected to Mac")
            } catch (e: Exception) {
                close()
                val wait = BACKOFF_MILLIS[minOf(failures, BACKOFF_MILLIS.size - 1)]
                failures++
                nextTry = System.currentTimeMillis() + wait
                Log.i("NB", "connect failed ($e), next try in ${wait / 1000}s")
            }
        } else {
            try {
                write(s.getOutputStream(), frame(key, withBattery(ctx, JSONObject().put("type", "ping")).toString()))
            } catch (e: Exception) {
                Log.i("NB", "ping failed: $e")
                close()
            }
        }
    }

    private fun frame(key: ByteArray, json: String): ByteArray {
        val nonce = ByteArray(12).also { rng.nextBytes(it) }
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        val sealed = nonce + c.doFinal(json.toByteArray(Charsets.UTF_8))
        return ByteBuffer.allocate(4 + sealed.size).putInt(sealed.size).put(sealed).array()
    }

    private fun write(out: OutputStream, data: ByteArray) {
        out.write(data)
        out.flush()
    }

    private fun connection(ctx: Context): Socket {
        socket?.takeIf { it.isConnected && !it.isClosed }?.let { return it }
        val key = keyBytes(ctx) ?: throw IllegalStateException("anahtar yok")
        val info = discover(ctx) ?: throw IllegalStateException("Mac yok")
        val s = Socket()
        s.connect(InetSocketAddress(info.host, info.port), 4000)
        s.tcpNoDelay = true
        s.keepAlive = true
        socket = s
        startReader(ctx, s)
        // tell the Mac who we are so it can show "connected"
        write(s.getOutputStream(), frame(key, withBattery(ctx, JSONObject().put("type", "hello").put("name", Build.MODEL)).toString()))
        flushMissed(ctx, key, s)
        setLink("connected")
        return s
    }

    /** Delivers notifications that piled up while the Mac was away. Each one is dropped only after it was written. */
    private fun flushMissed(ctx: Context, key: ByteArray, s: Socket) {
        val pending = MissedQueue.all(ctx)
        if (pending.isEmpty()) return
        for (m in pending) {
            write(s.getOutputStream(), frame(key, m.put("missed", true).toString()))
            MissedQueue.remove(ctx, m.optString("id"))
        }
        Log.i("NB", "delivered ${pending.size} missed notifications")
    }

    private fun close() {
        runCatching { socket?.close() }
        socket = null
        setLink(if (appCtx?.let { onWifi(it) } == true) "searching" else "nowifi")
    }

    /** Reads frames the Mac sends back (dismissals, replies, clipboard, find-phone) until the socket closes. */
    private fun startReader(ctx: Context, s: Socket) {
        Thread {
            try {
                val input = DataInputStream(s.getInputStream())
                while (true) {
                    val len = input.readInt()
                    if (len < 28 || len > 200_000) break
                    val buf = ByteArray(len).also { input.readFully(it) }
                    val key = Base64.decode(Settings.key(ctx), Base64.DEFAULT)
                    val c = Cipher.getInstance("AES/GCM/NoPadding")
                    c.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, buf.copyOfRange(0, 12)))
                    handle(ctx, JSONObject(String(c.doFinal(buf, 12, len - 12), Charsets.UTF_8)))
                }
            } catch (_: Exception) {
            }
            Log.i("NB", "reader closed")
            io.execute { if (socket === s) close() }
        }.apply { isDaemon = true }.start()
    }

    private fun handle(ctx: Context, json: JSONObject) {
        when (json.optString("type")) {
            "dismiss" -> NotifyListener.dismiss(json.getString("id"))
            "reply" -> {
                val ok = NotifyListener.reply(ctx, json.getString("id"), json.optString("text"))
                Settings.setStatus(ctx, if (ok) ctx.getString(R.string.status_reply_sent) + " · " + clock() else ctx.getString(R.string.status_reply_failed))
            }
            "clip" -> if (Settings.clipFromMac(ctx)) {
                val text = json.optString("text")
                if (text.isNotEmpty()) Handler(Looper.getMainLooper()).post {
                    (ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                        .setPrimaryClip(ClipData.newPlainText("AndPear", text))
                }
            }
            "find" -> FindPhone.start(ctx)
            "findStop" -> FindPhone.stop(ctx)
        }
    }

    @Suppress("DEPRECATION")
    private fun discover(ctx: Context): NsdServiceInfo? {
        val nsd = ctx.getSystemService(Context.NSD_SERVICE) as NsdManager
        val latch = CountDownLatch(1)
        var found: NsdServiceInfo? = null
        val listener = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(s: NsdServiceInfo) {
                if (found != null) return
                nsd.resolveService(s, object : NsdManager.ResolveListener {
                    override fun onResolveFailed(s: NsdServiceInfo, code: Int) {}
                    override fun onServiceResolved(s: NsdServiceInfo) {
                        if (found == null) { found = s; latch.countDown() }
                    }
                })
            }
            override fun onStartDiscoveryFailed(t: String, c: Int) { latch.countDown() }
            override fun onStopDiscoveryFailed(t: String, c: Int) {}
            override fun onDiscoveryStarted(t: String) {}
            override fun onDiscoveryStopped(t: String) {}
            override fun onServiceLost(s: NsdServiceInfo) {}
        }
        nsd.discoverServices(SERVICE, NsdManager.PROTOCOL_DNS_SD, listener)
        latch.await(6, TimeUnit.SECONDS)
        runCatching { nsd.stopServiceDiscovery(listener) }
        return found
    }
}
