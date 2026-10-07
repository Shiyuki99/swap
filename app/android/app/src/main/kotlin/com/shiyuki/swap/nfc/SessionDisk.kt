package com.shiyuki.swap.nfc

import android.content.Context

/** Minimal key-value seam so disk persistence stays unit-testable without Robolectric. */
interface SessionPrefs {
    fun save(session: PendingNfcSession)
    fun load(): PendingNfcSession?
    fun clear()
}

/** SharedPreferences-backed [SessionPrefs]. TTL enforcement stays in the store. */
class SharedPrefsSessionPrefs(context: Context) : SessionPrefs {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    override fun save(session: PendingNfcSession) {
        prefs.edit()
            .putString(KEY_ID, session.sessionId)
            .putString(KEY_SECRET, session.sessionSecret)
            .putString(KEY_URL, session.url)
            .putLong(KEY_CREATED, session.createdAtMillis)
            .putLong(KEY_EXPIRES, session.expiresAtMillis)
            .apply()
    }

    override fun load(): PendingNfcSession? {
        val id = prefs.getString(KEY_ID, null) ?: return null
        val secret = prefs.getString(KEY_SECRET, null) ?: return null
        val url = prefs.getString(KEY_URL, null) ?: return null
        if (!prefs.contains(KEY_CREATED) || !prefs.contains(KEY_EXPIRES)) return null
        return PendingNfcSession(
            sessionId = id,
            sessionSecret = secret,
            url = url,
            createdAtMillis = prefs.getLong(KEY_CREATED, 0L),
            expiresAtMillis = prefs.getLong(KEY_EXPIRES, 0L),
        )
    }

    override fun clear() {
        prefs.edit().clear().apply()
    }

    companion object {
        private const val PREFS_NAME = "swap_nfc_session"
        private const val KEY_ID = "session_id"
        private const val KEY_SECRET = "session_secret"
        private const val KEY_URL = "url"
        private const val KEY_CREATED = "created_at"
        private const val KEY_EXPIRES = "expires_at"
    }
}

/** Disk gateway used by the channel (save/clear) and the HCE service (load). */
object SessionDisk {
    fun save(context: Context, session: PendingNfcSession) = prefs(context).save(session)
    fun load(context: Context): PendingNfcSession? = prefs(context).load()
    fun clear(context: Context) = prefs(context).clear()

    private fun prefs(context: Context): SessionPrefs = SharedPrefsSessionPrefs(context)
}
