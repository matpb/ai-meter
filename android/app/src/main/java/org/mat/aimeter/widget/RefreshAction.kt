package org.mat.aimeter.widget

import android.content.Context
import androidx.glance.GlanceId
import androidx.glance.action.ActionParameters
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.updateAll
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import java.util.concurrent.TimeUnit
import org.mat.aimeter.requestRefresh

private const val REFRESH_CHECK_WORK_NAME = "refresh_check"

class RefreshAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        requestRefresh(context)

        WorkManager.getInstance(context).enqueueUniqueWork(
            REFRESH_CHECK_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<RefreshCheckWorker>()
                .setInitialDelay(65, TimeUnit.SECONDS)
                .build(),
        )

        AiMeterWidget().updateAll(context)
    }
}
