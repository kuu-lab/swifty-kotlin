package org.swiftykotlin.composeprobe

import androidx.compose.runtime.Composable
import androidx.compose.runtime.currentComposer

@Composable
fun Counter(renderer: CounterRenderer) {
    CounterLabel(renderer, listOf("Compose", "count").joinToString(" "))
}

@Composable
private fun CounterLabel(renderer: CounterRenderer, prefix: String) {
    renderer.render(currentComposer, prefix)
}
