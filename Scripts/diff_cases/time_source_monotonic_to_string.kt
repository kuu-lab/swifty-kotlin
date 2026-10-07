import kotlin.time.*

fun main() {
    println(TimeSource.Monotonic)
    println(TimeSource.Monotonic.toString())
    val source: TimeSource = TimeSource.Monotonic
    println(source)
    println(source.toString())
    val erased: Any = TimeSource.Monotonic
    println(erased)
    println(erased.toString())
    println("$erased")
}
