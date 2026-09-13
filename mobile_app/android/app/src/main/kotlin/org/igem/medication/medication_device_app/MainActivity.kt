package org.igem.medication.medication_device_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.igem.medication/platform")
            .setMethodCallHandler { call, result ->
                if (call.method == "androidSdkInt") result.success(Build.VERSION.SDK_INT)
                else result.notImplemented()
            }
    }
}
