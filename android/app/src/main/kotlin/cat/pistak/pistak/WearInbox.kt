package cat.pistak.pistak

import android.content.Context
import java.io.File
import java.io.FileOutputStream

/**
 * Durable inbox for commands received from the watch (one JSON per line).
 * Written by [WearListenerService] (fsync before the ack is sent), read and
 * trimmed by Flutter through the `pistak/wear` channel AFTER it has stored
 * the resulting events. Never loses a tap: worst case a command is replayed,
 * and replays are idempotent on the Dart side.
 */
object WearInbox {
    private const val FILE = "wear_inbox.jsonl"
    private val lock = Any()

    /** Called when new lines arrive (set while the Flutter UI is alive). */
    @Volatile var onChanged: (() -> Unit)? = null

    private fun file(ctx: Context) = File(ctx.filesDir, FILE)

    fun append(ctx: Context, line: String) {
        val clean = line.replace('\n', ' ')
        synchronized(lock) {
            FileOutputStream(file(ctx), true).use { out ->
                out.write((clean + "\n").toByteArray(Charsets.UTF_8))
                out.fd.sync()
            }
        }
        onChanged?.invoke()
    }

    fun read(ctx: Context): List<String> = synchronized(lock) {
        val f = file(ctx)
        if (!f.exists()) emptyList()
        else f.readLines(Charsets.UTF_8).filter { it.isNotBlank() }
    }

    fun remove(ctx: Context, done: List<String>) = synchronized(lock) {
        val remaining = read(ctx).toMutableList()
        for (d in done) remaining.remove(d)
        val f = file(ctx)
        val tmp = File(ctx.filesDir, "$FILE.tmp")
        FileOutputStream(tmp).use { out ->
            out.write(remaining.joinToString("") { it + "\n" }.toByteArray(Charsets.UTF_8))
            out.fd.sync()
        }
        if (!tmp.renameTo(f)) {
            f.delete(); tmp.renameTo(f)
        }
    }
}
