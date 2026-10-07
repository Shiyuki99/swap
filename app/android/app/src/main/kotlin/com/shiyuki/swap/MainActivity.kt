package com.shiyuki.swap

import com.shiyuki.swap.nfc.NfcMethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NfcMethodChannel.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }
}
