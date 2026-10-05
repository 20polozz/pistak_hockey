package cat.pistak.pistak

import android.util.Log
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Wearable
import com.google.android.gms.wearable.WearableListenerService
import org.json.JSONObject

/** Receives taps from the PISTAK watch app (wear_os/). */
class WearListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != PATH_COMMAND) return
        val json = String(event.data, Charsets.UTF_8)
        val id = try { JSONObject(json).getString("id") } catch (e: Exception) {
            Log.w(TAG, "malformed watch command ignored"); return
        }
        WearInbox.append(this, json) // durable first…
        Wearable.getMessageClient(this) // …then acknowledge to the watch
            .sendMessage(event.sourceNodeId, PATH_ACK, id.toByteArray(Charsets.UTF_8))
            .addOnFailureListener { Log.w(TAG, "ack failed (watch will resend)", it) }
    }

    companion object {
        const val TAG = "PistakWear"
        const val PATH_COMMAND = "/pistak/cmd"
        const val PATH_ACK = "/pistak/ack"
        const val PATH_STATE = "/pistak/state"
    }
}
