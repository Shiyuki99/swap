package com.shiyuki.swap.nfc

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.nfc.NfcAdapter
import android.nfc.cardemulation.CardEmulation
import android.util.Log
import com.shiyuki.swap.MainActivity
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
    private const val TAG = "SwapNfc"

    fun register(messenger: BinaryMessenger, activity: MainActivity) {
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
                        activity.setNfcSharingActive(true)
                    }
                    result.success(session != null)
                }
                "stopSession" -> {
                    PendingNfcSessionStore.shared.clear()
                    SessionDisk.clear(appContext)
                    activity.setNfcSharingActive(false)
                    result.success(true)
                }
                "setPreferred" -> result.success(applyPreferred(activity))
                "unsetPreferred" -> result.success(clearPreferred(activity))
                "allowsForegroundPreference" -> result.success(allowsForegroundPreference(activity))
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
    fun applyPreferred(activity: Activity): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return false
        val emulation = CardEmulation.getInstance(adapter)
        val component = ComponentName(activity, SwapHostApduService::class.java)
        val accepted = emulation.setPreferredService(activity, component)
        if (!accepted) {
            val allowed = allowsForegroundPreference(activity)
            Log.w(
                TAG,
                "setPreferredService rejected (activityResumed=${activity.hasWindowFocus()}, " +
                    "foregroundOverrideAllowed=$allowed)",
            )
        }
        return accepted
    }

    fun clearPreferred(activity: Activity): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return false
        val emulation = CardEmulation.getInstance(adapter)
        return emulation.unsetPreferredService(activity)
    }

    /**
     * False when the user forbids foreground apps overriding the default
     * wallet and our NDEF AID collides with a wallet-owned AID. In that
     * case setPreferred() fails and only a settings change
     * (Tap & pay → allow foreground override) can fix routing.
     */
    private fun allowsForegroundPreference(activity: Activity): Boolean {
        val adapter = NfcAdapter.getDefaultAdapter(activity) ?: return false
        val emulation = CardEmulation.getInstance(adapter)
        return emulation.categoryAllowsForegroundPreference(CardEmulation.CATEGORY_OTHER)
    }
}
