fun pipelineFor(
    context: Int,
    subject: Int,
    debugMode: Boolean = false
): String = if (debugMode) {
    "debug:$context"
} else {
    "fast:$subject"
}

fun main() {
    println(pipelineFor(1, 2))
    println(pipelineFor(1, 2, true))
}
