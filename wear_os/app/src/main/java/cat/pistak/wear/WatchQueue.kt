package cat.pistak.wear

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray

/**
 * Durable outbox of taps not yet confirmed by the phone (SharedPreferences,
 * committed synchronously). Survives the watch losing the phone, the app
 * being closed and reboots.
 */
class WatchQueue private constructor(context: Context) {
    private val prefs = context.getSharedPreferences("pistak_queue", Context.MODE_PRIVATE)
    private val _pending = MutableStateFlow(load())
    val pending: StateFlow<List<WatchCommand>> = _pending

    private fun load(): List<WatchCommand> {
        val arr = JSONArray(prefs.getString(KEY, "[]"))
        return (0 until arr.length()).map { WatchCommand.fromJson(arr.getString(it)) }
    }

    private fun save(list: List<WatchCommand>) {
        val arr = JSONArray()
        list.forEach { arr.put(it.toJson()) }
        prefs.edit().putString(KEY, arr.toString()).commit()
        _pending.value = list
    }

    @Synchronized fun add(c: WatchCommand) = save(_pending.value + c)

    @Synchronized fun remove(id: String) = save(_pending.value.filterNot { it.id == id })

    companion object {
        private const val KEY = "commands"
        @Volatile private var instance: WatchQueue? = null
        fun get(context: Context): WatchQueue =
            instance ?: synchronized(this) {
                instance ?: WatchQueue(context.applicationContext).also { instance = it }
            }
    }
}

/** Latest scoreboard from the phone (in memory + persisted). */
object WatchState {
    val score = MutableStateFlow(ScoreState())
}
