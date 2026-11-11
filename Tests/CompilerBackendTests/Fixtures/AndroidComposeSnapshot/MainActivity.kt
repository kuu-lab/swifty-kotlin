package org.swiftykotlin.composeprobe

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

class MainActivity : Activity() {
    private lateinit var count: ComposeCounterState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val root = LinearLayout(this)
        root.setOrientation(LinearLayout.VERTICAL)
        val label = TextView(this)
        val increment = Button(this)
        ComposeCounterState.setText(increment, "Increment")
        root.addView(label)
        root.addView(increment)
        setContentView(root)

        count = ComposeCounterState()
        count.observe {
            ComposeCounterState.setText(label, listOf("Compose count", count.value().toString()).joinToString(": "))
        }
        increment.setOnClickListener { count.increment() }
    }

    override fun onDestroy() {
        count.close()
        super.onDestroy()
    }
}
