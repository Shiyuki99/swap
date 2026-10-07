package com.shiyuki.swap.nfc

import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Method channel (swap/nfc) exposing the native HCE implementation to Dart.
 * startSession stores the parsed session pair; the HCE service is statically
 * registered in the manifest so no explicit service start is required.
 */
object NfcMethodChannel {
    private const val CHANNEL = "swap/nfc"

    fun register(messenger: BinaryMessenger, context: Context) {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(hasNfcHce(context))
                "isEnabled" -> result.success(isNfcEnabled(context))
                "startSession" -> {
                    val url = call.argument<String>("url")
                    val session = url?.let { PendingNfcSessionStore.shared.set(it) }
                    result.success(session != null)
                }
                "stopSession" -> {
                    PendingNfcSessionStore.shared.clear()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasNfcHce(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)

    private fun isNfcEnabled(context: Context): Boolean =
        NfcAdapter.getDefaultAdapter(context)?.isEnabled == true
}
