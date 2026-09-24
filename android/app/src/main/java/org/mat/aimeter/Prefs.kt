package org.mat.aimeter

import android.content.Context
import android.content.SharedPreferences

// SharedPreferences (not DataStore): small set of string values, no need for Flow/typed schema.
object Prefs {
    private const val FILE = "ai_meter"
    private const val KEY_PAYLOAD_JSON = "payload_json"
    private const val KEY_PAYLOAD_RECEIVED_AT = "payload_received_at"
    private const val KEY_SUB_STATUS = "sub_status"
    private const val KEY_SUB_AT = "sub_at"
    private const val KEY_REFRESH_REQUESTED_AT = "refresh_requested_at"
    private const val KEY_REFRESH_ERROR = "refresh_error"
    private const val KEY_WIDGET_TICK = "widget_tick"

    const val SUB_STATUS_OK = "subscribed"

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    // Lets callers (e.g. MainActivity) observe cross-process writes via OnSharedPreferenceChangeListener.
    fun sharedPreferences(context: Context): SharedPreferences = prefs(context)

    fun getPayloadJson(context: Context): String? = prefs(context).getString(KEY_PAYLOAD_JSON, null)

    fun setPayloadJson(context: Context, json: String) {
        prefs(context).edit()
            .putString(KEY_PAYLOAD_JSON, json)
            .putLong(KEY_PAYLOAD_RECEIVED_AT, System.currentTimeMillis() / 1000)
            .apply()
    }

    fun getPayloadReceivedAt(context: Context): Long? =
        prefs(context).getLong(KEY_PAYLOAD_RECEIVED_AT, -1L).takeIf { it >= 0 }

    fun getSubStatus(context: Context): String? = prefs(context).getString(KEY_SUB_STATUS, null)

    fun setSubStatus(context: Context, status: String) {
        prefs(context).edit()
            .putString(KEY_SUB_STATUS, status)
            .putLong(KEY_SUB_AT, System.currentTimeMillis() / 1000)
            .apply()
    }

    fun getSubAt(context: Context): Long? = prefs(context).getLong(KEY_SUB_AT, -1L).takeIf { it >= 0 }

    fun getRefreshRequestedAt(context: Context): Long? =
        prefs(context).getLong(KEY_REFRESH_REQUESTED_AT, -1L).takeIf { it >= 0 }

    fun setRefreshRequestedAt(context: Context, atMs: Long) {
        prefs(context).edit()
            .putLong(KEY_REFRESH_REQUESTED_AT, atMs)
            .remove(KEY_REFRESH_ERROR)
            .apply()
    }

    fun getRefreshError(context: Context): String? = prefs(context).getString(KEY_REFRESH_ERROR, null)

    fun setRefreshError(context: Context, message: String) {
        prefs(context).edit().putString(KEY_REFRESH_ERROR, message).apply()
    }

    // Bumped by RefreshCheckWorker so a NoReply timeout recomposes the widget even when no
    // other pref value changed (a bare time-based check wouldn't trigger a listener callback).
    fun getWidgetTick(context: Context): Long = prefs(context).getLong(KEY_WIDGET_TICK, 0L)

    fun setWidgetTick(context: Context, atMs: Long) {
        prefs(context).edit().putLong(KEY_WIDGET_TICK, atMs).apply()
    }
}
