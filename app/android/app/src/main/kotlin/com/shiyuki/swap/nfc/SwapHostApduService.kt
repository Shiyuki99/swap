package com.shiyuki.swap.nfc

import android.content.pm.ApplicationInfo
import android.nfc.cardemulation.HostApduService
import android.os.Bundle
import android.util.Log

/**
 * App-owned HCE service emulating an NFC Forum Type 4 NDEF tag.
 *
 * Serves a frozen NDEF URI + AAR snapshot from [PendingNfcSessionStore.shared]
 * for the current pending session. Works without Flutter attached. Never
 * performs network, Nearby, or permission work here — processCommandApdu
 * runs on the main thread and must not block.
 */
class SwapHostApduService : HostApduService() {

    private val processor = ApduProcessor(ndefFile = { activeNdefFile() })

    // Debug-gated without AGP BuildConfig (off in Flutter projects): never
    // log in release builds, and never log the session secret.
    private val debuggable: Boolean by lazy {
        0 != applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE
    }

    private fun activeNdefFile(): ByteArray? {
        val session = PendingNfcSessionStore.shared.active() ?: return null
        return NdefSnapshotBuilder.buildNdefFile(session.url, packageName)
    }

    override fun onCreate() {
        super.onCreate()
        // The system can bind this service on a field tap even after the app
        // process died. Restore the persisted session so app-closed handoff
        // keeps working; drop it when already expired.
        val saved = SessionDisk.load(this)
        if (saved != null) {
            PendingNfcSessionStore.shared.restore(saved)
            if (PendingNfcSessionStore.shared.active() == null) {
                PendingNfcSessionStore.shared.clear()
                SessionDisk.clear(this)
            }
        }
    }

    override fun processCommandApdu(commandApdu: ByteArray, extras: Bundle?): ByteArray {
        if (debuggable) {
            Log.d(TAG, "APDU ${commandApdu.size}B ${commandApdu.toHex()}")
        }
        return processor.process(commandApdu)
    }

    override fun onDeactivated(reason: Int) {
        if (debuggable) Log.d(TAG, "Deactivated, reason=$reason")
        processor.reset()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02X".format(it) }

    companion object {
        private const val TAG = "SwapNfc"
    }
}
