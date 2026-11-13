package org.swiftykotlin.composeprobe

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.BasicText
import androidx.compose.material3.Button
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.ComposeView

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val initial = mutableListOf<String>()
        for (index in 1..100) initial.add("Saved task " + index.toString())
        val tasks = mutableStateOf<List<String>>(initial)
        val draft = mutableStateOf("")
        val compose = ComposeView(this)
        compose.setContent { TaskList(tasks, draft) }
        setContentView(compose)
    }
}

@Composable
private fun TaskList(tasks: MutableState<List<String>>, draft: MutableState<String>) {
    Column {
        BasicText("Tasks")
        OutlinedTextField(
            value = draft.value,
            onValueChange = { value -> draft.value = value },
            label = { BasicText("New task") },
            singleLine = true
        )
        Button(onClick = {
            val title = draft.value.trim()
            if (title.isNotEmpty()) {
                val updated = mutableListOf(title)
                updated.addAll(tasks.value)
                tasks.value = updated
                draft.value = ""
            }
        }) {
            BasicText("Add task")
        }
        val visible = tasks.value
        BasicText("Task count: " + visible.size.toString())
        LazyColumn {
            items(visible.size) { index ->
                BasicText(visible[index])
            }
        }
    }
}
