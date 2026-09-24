package org.mat.pocketmeter.fcm

import android.util.Log
import androidx.glance.appwidget.updateAll
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.runBlocking
import org.mat.pocketmeter.Prefs
import org.mat.pocketmeter.core.IngestResult
import org.mat.pocketmeter.core.evaluateIngest
import org.mat.pocketmeter.subscribeToTopic
import org.mat.pocketmeter.widget.PocketMeterWidget

private const val TAG = "PocketMeterFcm"

// onMessageReceived already runs off the main thread (FCM's own executor); block on it so
// the widget update finishes before the service can be torn down.
class PocketMeterMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        when (val result = evaluateIngest(message.data, Prefs.getPayloadJson(applicationContext))) {
            is IngestResult.Accept -> {
                Prefs.setPayloadJson(applicationContext, result.rawJson)
                runBlocking { PocketMeterWidget().updateAll(applicationContext) }
            }
            is IngestResult.Reject -> Log.w(TAG, "Rejected payload: ${result.reason}")
        }
    }

    override fun onNewToken(token: String) {
        subscribeToTopic(applicationContext)
    }
}
