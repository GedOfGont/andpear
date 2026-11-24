package com.notifybridge.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper

/** "Find my phone": rings on the alarm stream at full volume until stopped, or after a minute. */
object FindPhone {
    private const val CHANNEL = "find"
    private const val NOTIF_ID = 4242
    private const val MAX_MILLIS = 60_000L

    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private var appCtx: Context? = null
    private val autoStop = Runnable { appCtx?.let { stop(it) } }

    fun start(ctx: Context) {
        val app = ctx.applicationContext
        appCtx = app
        handler.post {
            stopNow(app)
            val audio = app.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0) }
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(app, uri)?.apply {
                audioAttributes = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ALARM)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
                isLooping = true
                play()
            }
            showNotification(app)
            handler.postDelayed(autoStop, MAX_MILLIS)
        }
    }

    fun stop(ctx: Context) {
        val app = ctx.applicationContext
        handler.post { stopNow(app) }
    }

    private fun stopNow(app: Context) {
        handler.removeCallbacks(autoStop)
        runCatching { ringtone?.stop() }
        ringtone = null
        (app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(NOTIF_ID)
    }

    private fun showNotification(app: Context) {
        val nm = app.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannel(NotificationChannel(CHANNEL, app.getString(R.string.find_channel), NotificationManager.IMPORTANCE_HIGH))
        val stop = PendingIntent.getBroadcast(
            app, 0, Intent(app, StopFindReceiver::class.java).setPackage(app.packageName),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val n = android.app.Notification.Builder(app, CHANNEL)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(app.getString(R.string.find_title))
            .setContentText(app.getString(R.string.find_text))
            .setAutoCancel(true)
            .setTimeoutAfter(MAX_MILLIS)   // disappears by itself even if the process dies while ringing
            .addAction(android.app.Notification.Action.Builder(null, app.getString(R.string.find_stop), stop).build())
            .build()
        runCatching { nm.notify(NOTIF_ID, n) }
    }
}

class StopFindReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = FindPhone.stop(context)
}
