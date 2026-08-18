@kotlin.ExperimentalContextParameters
fun markedWithContextParameters(): Int = 42

@OptIn(kotlin.ExperimentalContextParameters::class)
fun main() {
    println(markedWithContextParameters())
}
