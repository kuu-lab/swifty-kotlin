package org.swiftykotlin.composeprobe

import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import androidx.activity.ComponentActivity
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.platform.ComposeView

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val count = mutableIntStateOf(0)
        val column = LinearLayout(this)
        column.setOrientation(LinearLayout.VERTICAL)
        val compose = ComposeView(this)
        compose.setContent { Counter(count) }
        column.addView(compose)
        val increment = Button(this)
        increment.setText("Increment")
        increment.setOnClickListener { count.intValue = count.intValue + 1 }
        column.addView(increment)
        setContentView(column)
    }
}

@Composable
private fun Counter(count: MutableIntState) {
    BasicText(listOf("Compose count", count.intValue.toString()).joinToString(": "))
}
