package com.pedro.escaner

import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var volumeCaptureEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "escaner/volume_keys",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setEnabled") {
                    volumeCaptureEnabled = call.arguments as? Boolean ?: false
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val isVolume = event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.keyCode == KeyEvent.KEYCODE_VOLUME_UP
        if (volumeCaptureEnabled && isVolume) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                volumeChannel?.invokeMethod("pressed", null)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
