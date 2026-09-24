package org.mat.aimeter.widget

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import org.mat.aimeter.Prefs

// Re-renders the widget ~65s after a refresh request so a NoReply status shows up
// even if no new FCM payload ever arrives.
class RefreshCheckWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        // A time-only change wouldn't otherwise trigger the prefs listener recomposition.
        Prefs.setWidgetTick(applicationContext, System.currentTimeMillis())
        AiMeterWidget().updateAll(applicationContext)
        return Result.success()
    }
}
