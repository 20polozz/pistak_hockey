package cat.pistak.wear

import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService

/** Receives ACKs (→ remove from the outbox) and scoreboard updates. */
class PhoneListenerService : WearableListenerService() {
    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            Protocol.PATH_ACK -> WatchQueue.get(this).remove(String(event.data))
            Protocol.PATH_STATE -> WatchState.score.value = ScoreState.fromJson(String(event.data))
        }
    }
}
