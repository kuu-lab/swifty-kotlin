package org.swiftykotlin.androidprobe

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.TextView

class MainActivity : Activity() {
    private var count = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.counter)
        val label = findViewById<TextView>(R.id.count)
        val button = findViewById<Button>(R.id.increment)
        button.setOnClickListener {
            count += 1
            label.setText("Count: ${count}")
        }
    }
}
