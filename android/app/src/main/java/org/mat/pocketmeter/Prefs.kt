package org.mat.pocketmeter

import android.content.Context
import android.content.SharedPreferences

// SharedPreferences (not DataStore): small set of string values, no need for Flow/typed schema.
object Prefs {
    private const val FILE = "pocket_meter"
    private const val KEY_PAYLOAD_JSON = "payload_json"
    private const val KEY_PAYLOAD_RECEIVED_AT = "payload_received_at"
    private const val KEY_SUB_STATUS = "sub_status"
    private const val KEY_SUB_AT = "sub_at"

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
}
