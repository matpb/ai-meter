package org.mat.aimeter

import android.app.Application
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging

private const val TAG = "AiMeterApp"

class AiMeterApp : Application() {
    override fun onCreate() {
        super.onCreate()
        subscribeToTopic(this)
    }
}

// Idempotent: FCM no-ops if already subscribed. Called on every process start and from
// onNewToken so a token refresh re-establishes the topic subscription.
fun subscribeToTopic(context: android.content.Context) {
    FirebaseMessaging.getInstance().subscribeToTopic(BuildConfig.FCM_TOPIC)
        .addOnCompleteListener { task ->
            if (task.isSuccessful) {
                Prefs.setSubStatus(context, Prefs.SUB_STATUS_OK)
            } else {
                Log.w(TAG, "Topic subscribe failed", task.exception)
                Prefs.setSubStatus(context, task.exception?.message ?: "error")
            }
        }
}
