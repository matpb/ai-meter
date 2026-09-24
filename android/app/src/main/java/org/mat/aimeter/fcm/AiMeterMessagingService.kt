package org.mat.aimeter.fcm

import android.util.Log
import androidx.glance.appwidget.updateAll
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import kotlinx.coroutines.runBlocking
import org.mat.aimeter.Prefs
import org.mat.aimeter.core.IngestResult
import org.mat.aimeter.core.evaluateIngest
import org.mat.aimeter.subscribeToTopic
import org.mat.aimeter.widget.AiMeterWidget

private const val TAG = "AiMeterFcm"

// onMessageReceived already runs off the main thread (FCM's own executor); block on it so
// the widget update finishes before the service can be torn down.
class AiMeterMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        when (val result = evaluateIngest(message.data, Prefs.getPayloadJson(applicationContext))) {
            is IngestResult.Accept -> {
                Prefs.setPayloadJson(applicationContext, result.rawJson)
                runBlocking { AiMeterWidget().updateAll(applicationContext) }
            }
            is IngestResult.Reject -> Log.w(TAG, "Rejected payload: ${result.reason}")
        }
    }

    override fun onNewToken(token: String) {
        subscribeToTopic(applicationContext)
    }
}
