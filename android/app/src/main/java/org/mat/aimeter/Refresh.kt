package org.mat.aimeter

import android.content.Context
import com.google.firebase.database.FirebaseDatabase
import com.google.firebase.database.ServerValue
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout

// True only when a Gradle/local.properties refresh key was baked into this build.
object RefreshConfig {
    val enabled: Boolean get() = BuildConfig.REFRESH_KEY.isNotBlank()
}

// Writes the refresh request and records the outcome in Prefs; shared by MainActivity and the widget.
suspend fun requestRefresh(context: Context, timeoutMs: Long = 10_000L) {
    val requestedAt = System.currentTimeMillis()
    try {
        withTimeout(timeoutMs) {
            FirebaseDatabase.getInstance()
                .getReference("refresh")
                .child(BuildConfig.REFRESH_KEY)
                .setValue(ServerValue.TIMESTAMP)
                .await()
        }
        Prefs.setRefreshRequestedAt(context, requestedAt)
    } catch (e: TimeoutCancellationException) {
        Prefs.setRefreshError(context, "timed out")
    } catch (e: Exception) {
        Prefs.setRefreshError(context, e.message ?: "refresh failed")
    }
}
