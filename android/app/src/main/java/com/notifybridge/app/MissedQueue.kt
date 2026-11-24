package com.notifybridge.app

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * Notifications the Mac could not receive (asleep, off, or on another network).
 * Kept on disk and delivered, flagged as "missed", the next time the Mac connects.
 */
object MissedQueue {
    private const val MAX = 50
    private const val MAX_AGE_MS = 24L * 60 * 60 * 1000

    private fun prefs(c: Context) = c.getSharedPreferences("nb", Context.MODE_PRIVATE)

    private fun load(c: Context): List<JSONObject> {
        val raw = prefs(c).getString("missed", null) ?: return emptyList()
        return runCatching {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getJSONObject(it) }
        }.getOrDefault(emptyList())
    }

    private fun save(c: Context, list: List<JSONObject>) {
        prefs(c).edit().putString("missed", JSONArray(list).toString()).putInt("queued", list.size).apply()
    }

    /** Adds or replaces (same notification id) a post; the oldest entries fall off beyond 50. */
    @Synchronized fun add(c: Context, msg: JSONObject) {
        val id = msg.optString("id")
        val list = load(c).filter { it.optString("id") != id }.toMutableList()
        list.add(msg)
        while (list.size > MAX) list.removeAt(0)
        save(c, list)
    }

    /** The user already dealt with it on the phone, so the Mac does not need it any more. */
    @Synchronized fun remove(c: Context, id: String) = save(c, load(c).filter { it.optString("id") != id })

    @Synchronized fun all(c: Context): List<JSONObject> {
        val cutoff = System.currentTimeMillis() - MAX_AGE_MS
        return load(c).filter { it.optLong("ts", System.currentTimeMillis()) >= cutoff }
    }

    fun count(c: Context): Int = all(c).size
}
