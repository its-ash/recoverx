package com.ashvinijangid.recoverx

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val worker = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "recoverx/media")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "videoFrames" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("args", "path is required", null)
                            return@setMethodCallHandler
                        }
                        val count = call.argument<Int>("count") ?: 4
                        val size = call.argument<Int>("size") ?: 224
                        // Decoding is slow; keep it off the UI thread.
                        worker.execute {
                            try {
                                val frames = VideoFrames.sample(path, count, size)
                                runOnUiThread { result.success(frames) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("frames", e.message, null) }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        worker.shutdownNow()
        super.onDestroy()
    }
}
