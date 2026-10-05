package cat.pistak.wear

import android.os.Bundle
import android.os.VibrationEffect
import android.os.Vibrator
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private val Lime = Color(0xFFB8F23A)
private val HomeBlue = Color(0xFF3B8BFF)
private val AwayOrange = Color(0xFFFF8A3D)
private val Yellow = Color(0xFFF5C518)
private val BlueCard = Color(0xFF2EA8FF)
private val Red = Color(0xFFE5484D)

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val queue = WatchQueue.get(this)
        val link = PhoneLink(this)
        setContent { MaterialTheme { WatchScreen(queue, link, ::buzz) } }
    }

    private fun buzz() {
        @Suppress("DEPRECATION")
        (getSystemService(VIBRATOR_SERVICE) as? Vibrator)
            ?.vibrate(VibrationEffect.createOneShot(40, VibrationEffect.DEFAULT_AMPLITUDE))
    }
}

private fun fmt(ms: Long): String {
    val s = (ms / 1000).coerceAtLeast(0)
    return "%02d:%02d".format(s / 60, s % 60)
}

@Composable
fun WatchScreen(queue: WatchQueue, link: PhoneLink, buzz: () -> Unit) {
    val scope = rememberCoroutineScope()
    val pending by queue.pending.collectAsState()
    val score by WatchState.score.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }

    // Repaint the clock; retry sending the outbox every few seconds.
    LaunchedEffect(Unit) {
        var tick = 0
        while (true) {
            now = System.currentTimeMillis()
            if (tick++ % 10 == 0 && queue.pending.value.isNotEmpty()) link.flush()
            delay(500)
        }
    }

    fun send(cmd: String, team: String? = null, color: String? = null) {
        buzz()
        queue.add(WatchCommand.create(cmd, team, color)) // durable before anything else
        scope.launch { link.flush() }
    }

    ScalingLazyColumn(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        item {
            Text(fmt(score.matchTimeNow(now)), fontSize = 30.sp, fontWeight = FontWeight.Black,
                color = if (score.running) Color.White else Color.Gray)
        }
        item {
            Text("${score.home} - ${score.away}", fontSize = 22.sp, fontWeight = FontWeight.Bold)
        }
        item {
            Text(
                if (pending.isEmpty()) score.label else "${score.label} · ⇡${pending.size}",
                fontSize = 12.sp, color = Lime, textAlign = TextAlign.Center,
            )
        }
        item { Pair("GOL L", "GOL V").let { (a, b) -> TwoButtons(a, HomeBlue, { send("goal", "home") }, b, AwayOrange) { send("goal", "away") } } }
        item { TwoButtons("FALTA L", HomeBlue, { send("foul", "home") }, "FALTA V", AwayOrange) { send("foul", "away") } }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                CardButton("G", Yellow) { send("card", color = "yellow") }
                CardButton("B", BlueCard) { send("card", color = "blue") }
                CardButton("R", Red) { send("card", color = "red") }
            }
        }
        item { TwoButtons("TM L", HomeBlue, { send("timeout", "home") }, "TM V", AwayOrange) { send("timeout", "away") } }
        item {
            Button(
                onClick = { send(if (score.running) "pause" else "resume") },
                colors = ButtonDefaults.buttonColors(backgroundColor = Lime),
                modifier = Modifier.fillMaxWidth(0.8f).height(44.dp),
            ) { Text(if (score.running) "PAUSA" else "REPRENDRE", color = Color.Black, fontWeight = FontWeight.Bold) }
        }
        item {
            Button(
                onClick = { send("incident") },
                colors = ButtonDefaults.buttonColors(backgroundColor = Color(0xFF2A2F3A)),
                modifier = Modifier.fillMaxWidth(0.8f).height(40.dp).padding(bottom = 8.dp),
            ) { Text("INCIDÈNCIA", fontSize = 12.sp) }
        }
    }
}

@Composable
private fun TwoButtons(a: String, ca: Color, onA: () -> Unit, b: String, cb: Color, onB: () -> Unit) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        Button(onClick = onA, colors = ButtonDefaults.buttonColors(backgroundColor = ca),
            modifier = Modifier.height(44.dp).fillMaxWidth(0.42f)) { Text(a, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        Button(onClick = onB, colors = ButtonDefaults.buttonColors(backgroundColor = cb),
            modifier = Modifier.height(44.dp).fillMaxWidth(0.72f)) { Text(b, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
    }
}

@Composable
private fun CardButton(label: String, color: Color, onClick: () -> Unit) {
    Button(onClick = onClick, colors = ButtonDefaults.buttonColors(backgroundColor = color),
        modifier = Modifier.height(40.dp)) { Text(label, color = Color.Black, fontWeight = FontWeight.Black) }
}
