package com.notifybridge.app

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.os.Bundle
import java.util.concurrent.ConcurrentHashMap
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.util.Base64
import org.json.JSONObject
import java.io.ByteArrayOutputStream

class NotifyListener : NotificationListenerService() {
    override fun onListenerConnected() { instance = this; Sender.start(this) }
    override fun onListenerDisconnected() { if (instance === this) instance = null }

    private fun skip(sbn: StatusBarNotification): Boolean =
        sbn.packageName == packageName || sbn.packageName in Settings.disabled(this)

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        if (skip(sbn)) return
        if (Settings.skipWhenScreenOn(this) && (getSystemService(POWER_SERVICE) as android.os.PowerManager).isInteractive) return
        val n = sbn.notification
        if (n.flags and Notification.FLAG_GROUP_SUMMARY != 0) return
        if (n.flags and Notification.FLAG_ONGOING_EVENT != 0) return
        val extras = n.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return
        val label = runCatching {
            packageManager.getApplicationLabel(packageManager.getApplicationInfo(sbn.packageName, 0)).toString()
        }.getOrDefault(sbn.packageName)
        val msg = JSONObject()
            .put("type", "post").put("id", sbn.key).put("pkg", sbn.packageName)
            .put("ts", System.currentTimeMillis())
            .put("app", label).put("title", title).put("text", text)
        icon(sbn.packageName)?.let { msg.put("icon", it) }
        val reply = replyAction(n)
        if (reply != null) {
            replies[sbn.key] = reply
            msg.put("reply", true)
        }
        Sender.send(this, msg)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        replies.remove(sbn.key)
        if (skip(sbn)) return
        Sender.send(this, JSONObject().put("type", "remove").put("id", sbn.key))
    }

    /** The notification's inline-reply action (messaging apps), preferring the one marked as REPLY. */
    private fun replyAction(n: Notification): Notification.Action? {
        val candidates = n.actions?.filter { a -> a.remoteInputs?.any { it.allowFreeFormInput } == true }.orEmpty()
        return candidates.firstOrNull { it.semanticAction == Notification.Action.SEMANTIC_ACTION_REPLY }
            ?: candidates.firstOrNull()
    }

    private fun icon(pkg: String): String? = iconCache.getOrPut(pkg) {
        runCatching {
            val d = packageManager.getApplicationIcon(pkg)
            val bmp = Bitmap.createBitmap(96, 96, Bitmap.Config.ARGB_8888)
            d.setBounds(0, 0, 96, 96)
            d.draw(Canvas(bmp))
            val out = ByteArrayOutputStream()
            bmp.compress(Bitmap.CompressFormat.PNG, 100, out)
            Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP)
        }.getOrDefault("")
    }.ifEmpty { null }

    companion object {
        @Volatile var instance: NotifyListener? = null
        private val replies = ConcurrentHashMap<String, Notification.Action>()

        /** Fires the app's own reply action with the text typed on the Mac. Returns false if it is gone. */
        fun reply(ctx: Context, key: String, text: String): Boolean {
            val action = replies[key] ?: return false
            val inputs = action.remoteInputs ?: return false
            val input = inputs.firstOrNull { it.allowFreeFormInput } ?: return false
            return runCatching {
                val intent = Intent()
                val results = Bundle().apply { putCharSequence(input.resultKey, text) }
                RemoteInput.addResultsToIntent(inputs, intent, results)
                action.actionIntent.send(ctx, 0, intent)
                true
            }.getOrDefault(false)
        }
        private val iconCache = HashMap<String, String>()

        /** Called when the Mac user dismisses or clicks a banner. */
        fun dismiss(key: String) {
            runCatching { instance?.cancelNotification(key) }
        }
    }
}
