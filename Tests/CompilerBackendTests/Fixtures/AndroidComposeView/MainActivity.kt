package org.swiftykotlin.composeprobe

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.Button
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.ComposeView

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val count = mutableIntStateOf(0)
        val compose = ComposeView(this)
        compose.setContent { Counter(count) }
        setContentView(compose)
    }
}

@Composable
private fun Counter(count: MutableIntState) {
    Column {
        BasicText(listOf("Compose count", count.intValue.toString()).joinToString(": "))
        Button(onClick = { count.intValue = count.intValue + 1 }) {
            BasicText("Increment")
        }
    }
}
