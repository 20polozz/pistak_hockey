package cat.pistak.wear

import org.json.JSONObject
import java.util.UUID

/** Wire protocol shared with the phone (android/…/WearBridge.kt). */
object Protocol {
    const val PATH_COMMAND = "/pistak/cmd"   // watch → phone
    const val PATH_ACK = "/pistak/ack"       // phone → watch (payload: command id)
    const val PATH_STATE = "/pistak/state"   // phone → watch (scoreboard JSON)
}

/**
 * One tap on the watch. The id is generated HERE, so if the phone receives
 * the same command twice (lost ack) it is stored only once.
 */
data class WatchCommand(
    val id: String,
    val cmd: String,
    val team: String? = null,
    val color: String? = null,
    val at: Long,
) {
    fun toJson(): String = JSONObject().apply {
        put("id", id)
        put("cmd", cmd)
        team?.let { put("team", it) }
        color?.let { put("color", it) }
        put("at", at)
    }.toString()

    companion object {
        fun create(cmd: String, team: String? = null, color: String? = null) =
            WatchCommand(UUID.randomUUID().toString(), cmd, team, color, System.currentTimeMillis())

        fun fromJson(s: String): WatchCommand {
            val o = JSONObject(s)
            return WatchCommand(
                o.getString("id"), o.getString("cmd"),
                o.optString("team").ifEmpty { null },
                o.optString("color").ifEmpty { null },
                o.getLong("at"),
            )
        }
    }
}

/** Scoreboard pushed by the phone. Clock is recomputed from timestamps. */
data class ScoreState(
    val home: Int = 0,
    val away: Int = 0,
    val label: String = "",
    val running: Boolean = false,
    val matchMs: Long = 0,
    val atMs: Long = 0,
) {
    fun matchTimeNow(now: Long): Long = if (running) matchMs + (now - atMs).coerceAtLeast(0) else matchMs

    companion object {
        fun fromJson(s: String): ScoreState {
            val o = JSONObject(s)
            return ScoreState(
                o.optInt("home"), o.optInt("away"), o.optString("label"),
                o.optBoolean("running"), o.optLong("matchMs"), o.optLong("atMs"),
            )
        }
    }
}
