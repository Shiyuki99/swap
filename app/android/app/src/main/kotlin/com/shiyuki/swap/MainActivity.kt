package com.shiyuki.swap

import com.shiyuki.swap.nfc.NfcMethodChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /**
     * True while a swap is sharing via NFC. Foreground card-emulation
     * preference is applied from onResume only while sharing: AOSP rejects
     * the request unless the calling UID is foreground, and applying it
     * while idle would make SWAP win routing for unrelated taps.
     */
    private var nfcSharingActive = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NfcMethodChannel.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }

    fun setNfcSharingActive(active: Boolean) {
        nfcSharingActive = active
        if (active) NfcMethodChannel.applyPreferred(this)
    }

    override fun onResume() {
        super.onResume()
        if (nfcSharingActive) NfcMethodChannel.applyPreferred(this)
    }

    override fun onPause() {
        NfcMethodChannel.clearPreferred(this)
        super.onPause()
    }
}
