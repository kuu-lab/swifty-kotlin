// KUU-1311: compare stable stack-trace properties across JVM and native frames.
package traces

class CustomTraceException : RuntimeException("custom")

fun main() {
    val exception = IllegalStateException("e")
    val trace = exception.stackTraceToString()
    println(trace.startsWith("java.lang.IllegalStateException: e\n\tat "))
    println(trace == exception.stackTraceToString())
    println(RuntimeException().stackTraceToString().startsWith("java.lang.RuntimeException\n\tat "))
    println(CustomTraceException().stackTraceToString().startsWith("traces.CustomTraceException: custom\n\tat "))
}
