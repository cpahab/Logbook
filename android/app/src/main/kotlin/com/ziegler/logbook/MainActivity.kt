package com.ziegler.logbook

import android.content.Intent
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {

    companion object {
        var pendingGpxPath: String? = null
    }

    private val channelName = "com.ziegler.logbook/gpx_share"
    private var methodChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            if (call.method == "getPendingGpxPath") {
                result.success(pendingGpxPath)
                pendingGpxPath = null
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action ?: return
        if (action != Intent.ACTION_VIEW && action != Intent.ACTION_SEND) return

        val uri = if (action == Intent.ACTION_SEND) {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        } else {
            intent.data
        } ?: return

        try {
            // Resolve display name for the file.
            var fileName = "shared_track.gpx"
            contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME),
                null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) fileName = cursor.getString(idx)
                }
            }
            if (!fileName.endsWith(".gpx", ignoreCase = true)) fileName += ".gpx"

            // Copy bytes to a stable internal location.
            val inboxDir = File(filesDir, "gpx_inbox").apply { mkdirs() }
            val dest = File(inboxDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }

            val stablePath = dest.absolutePath
            val channel = methodChannel
            if (channel != null) {
                // Engine is running — emit directly.
                channel.invokeMethod("onGpxFile", mapOf("path" to stablePath))
            } else {
                // Cold start — engine not ready yet; Dart will pull via getPendingGpxPath.
                pendingGpxPath = stablePath
            }
        } catch (_: Exception) {
            // Ignore — bad URI or IO error; user will see nothing rather than a crash.
        }
    }
}
