package com.notifybridge.app

import android.content.Context

object Settings {
    private fun prefs(c: Context) = c.getSharedPreferences("nb", Context.MODE_PRIVATE)

    fun key(c: Context): String = prefs(c).getString("key", "") ?: ""
    fun setKey(c: Context, k: String) = prefs(c).edit().putString("key", k.trim()).apply()
    fun status(c: Context): String {
        val s = prefs(c).getString("status", null)
        // older builds stored raw protocol names like "Gönderildi: remove"
        return if (s == null || s.startsWith("Gönderildi: ")) c.getString(R.string.status_none) else s
    }
    fun setStatus(c: Context, s: String) = prefs(c).edit().putString("status", s).apply()

    /** Don't forward notifications while the phone screen is on (the user is already looking at it). */
    fun skipWhenScreenOn(c: Context): Boolean = prefs(c).getBoolean("skipScreenOn", false)
    fun setSkipWhenScreenOn(c: Context, v: Boolean) = prefs(c).edit().putBoolean("skipScreenOn", v).apply()

    /** Accept clipboard text sent from the Mac. Off by default: clipboards often hold secrets. */
    fun clipFromMac(c: Context): Boolean = prefs(c).getBoolean("clipFromMac", false)
    fun setClipFromMac(c: Context, v: Boolean) = prefs(c).edit().putBoolean("clipFromMac", v).apply()

    /** "connected", "searching" or "nowifi": what the link to the Mac is doing right now. */
    fun link(c: Context): String = prefs(c).getString("link", "searching") ?: "searching"
    fun setLink(c: Context, v: String) = prefs(c).edit().putString("link", v).apply()

    /** Notifications waiting for the Mac (see MissedQueue). */
    fun queued(c: Context): Int = prefs(c).getInt("queued", 0)

    /** Packages the user switched off. Everything else is forwarded. */
    fun disabled(c: Context): Set<String> = prefs(c).getStringSet("disabled", emptySet()) ?: emptySet()
    fun setEnabled(c: Context, pkg: String, enabled: Boolean) {
        val s = disabled(c).toMutableSet()
        if (enabled) s.remove(pkg) else s.add(pkg)
        prefs(c).edit().putStringSet("disabled", s).apply()
    }
}
