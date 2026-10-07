package com.shiyuki.swap.nfc

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Method channel (swap/nfc) exposing the native HCE implementation to Dart.
 * startSession stores the parsed session pair in memory and on disk; the HCE
 * service is statically registered in the manifest so no explicit service
 * start is required.
 */
object NfcMethodChannel {
    private const val CHANNEL = "swap/nfc"

    fun register(messenger: BinaryMessenger, activity: Activity) {
        val appContext = activity.applicationContext
        MethodChannel(messenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(hasNfcHce(appContext))
                "isEnabled" -> result.success(isNfcEnabled(appContext))
                "startSession" -> {
                    val url = call.argument<String>("url")
                    val session = url?.let { PendingNfcSessionStore.shared.set(it) }
                    if (session != null) {
                        SessionDisk.save(appContext, session)
                    }
                    result.success(session != null)
                }
                "stopSession" -> {
                    PendingNfcSessionStore.shared.clear()
                    SessionDisk.clear(appContext)
                    result.success(true)
                }
                "setPreferred" -> result.success(setPreferred(activity))
                "unsetPreferred" -> result.success(unsetPreferred(activity))
                else -> result.notImplemented()
            }
        }
    }

    private fun hasNfcHce(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_NFC_HOST_CARD_EMULATION)

    private fun isNfcEnabled(context: Context): Boolean =
        NfcAdapter.getDefaultAdapter(context)?.isEnabled == true

    /**
     * Routes our AIDs to SwapHostApduService while the calling activity is
     * foreground. This wins AID routing against other NDEF-HCE apps (but not
     * payment AIDs owned by wallets — readers fetching a URL never select
     * those). Must be called from a resumed activity; returns false otherwise.
     */
    private fun setPreferred(activity: Activity): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return false
        val emulation = CardEmulation.getInstance(adapter)
        val component = ComponentName(activity, SwapHostApduService::class.java)
        return emulation.setPreferredService(activity, component)
    }

    private fun unsetPreferred(activity: Activity): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return false
        val emulation = CardEmulation.getInstance(adapter)
        return emulation.unsetPreferredService(activity)
    }
}
