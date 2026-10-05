package cat.pistak.pistak

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.android.gms.wearable.Wearable
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pistak/wear")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readInbox" -> result.success(WearInbox.read(this))
                    "removeFromInbox" -> {
                        WearInbox.remove(this, call.arguments<List<String>>() ?: emptyList())
                        result.success(null)
                    }
                    "sendState" -> {
                        sendState(call.arguments<String>() ?: "{}")
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("wear", e.message, null)
            }
        }
        WearInbox.onChanged = { main.post { channel?.invokeMethod("inboxChanged", null) } }
    }

    private fun sendState(json: String) {
        val bytes = json.toByteArray(Charsets.UTF_8)
        Wearable.getNodeClient(this).connectedNodes
            .addOnSuccessListener { nodes ->
                for (n in nodes) {
                    Wearable.getMessageClient(this)
                        .sendMessage(n.id, WearListenerService.PATH_STATE, bytes)
                }
            }
            .addOnFailureListener { Log.d(WearListenerService.TAG, "no wearable API: ${it.message}") }
    }

    override fun onDestroy() {
        WearInbox.onChanged = null
        channel = null
        super.onDestroy()
    }
}
