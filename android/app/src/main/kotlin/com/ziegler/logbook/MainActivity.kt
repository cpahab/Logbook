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
        // onCreate only runs for a fresh Activity/engine instance (launchMode
        // "singleTop" routes re-launches of a running instance to onNewIntent
        // below), so the Dart side is guaranteed not to have registered its
        // method call handler yet. Pushing via invokeMethod here would race
        // main()'s async startup and could be dropped with no listener
        // attached — buffer the path instead and let Dart pull it once ready.
        handleIntent(intent, coldStart = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        // The engine (and Dart's handler) were already running before this
        // intent arrived, so pushing directly is safe.
        handleIntent(intent, coldStart = false)
    }

    private fun handleIntent(intent: Intent?, coldStart: Boolean) {
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

            // The shared URI points into the sending app's content provider and
            // is only guaranteed valid for this call — copy the bytes now to a
            // location we own so the Dart side can read it later at its own pace.
            val inboxDir = File(filesDir, "gpx_inbox").apply { mkdirs() }
            val dest = File(inboxDir, fileName)
            contentResolver.openInputStream(uri)?.use { input ->
                dest.outputStream().use { output -> input.copyTo(output) }
            }

            val stablePath = dest.absolutePath
            if (coldStart) {
                // Dart will pull this via getPendingGpxPath once it has
                // subscribed to the stream (see GpxShareService).
                pendingGpxPath = stablePath
            } else {
                methodChannel?.invokeMethod("onGpxFile", mapOf("path" to stablePath))
            }
        } catch (_: Exception) {
            // Ignore — bad URI or IO error; user will see nothing rather than a crash.
        }
    }
}
