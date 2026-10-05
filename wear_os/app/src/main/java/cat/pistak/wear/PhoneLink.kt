package cat.pistak.wear

import android.content.Context
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.tasks.await

/** Sends pending commands to the phone; each one is removed only on ACK. */
class PhoneLink(private val context: Context) {
    suspend fun flush(): Boolean {
        val queue = WatchQueue.get(context)
        val pending = queue.pending.value
        if (pending.isEmpty()) return true
        return try {
            val nodes = Wearable.getNodeClient(context).connectedNodes.await()
            if (nodes.isEmpty()) return false
            val client = Wearable.getMessageClient(context)
            for (c in pending) {
                for (n in nodes) {
                    client.sendMessage(n.id, Protocol.PATH_COMMAND, c.toJson().toByteArray()).await()
                }
            }
            true
        } catch (e: Exception) {
            false // phone not reachable: commands stay queued
        }
    }
}
