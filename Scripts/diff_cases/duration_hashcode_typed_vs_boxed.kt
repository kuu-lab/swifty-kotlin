// KUU-645: Duration.hashCode() must agree on the typed, boxed/Any, and generic
// paths, using Kotlin's packed rawValue.
import kotlin.time.Duration.Companion.seconds

fun <T> genericHash(x: T): Int = x.hashCode()

fun main() {
    val d = 5.seconds
    println(d.hashCode())
    println(d.hashCode() == (d as Any).hashCode())
    println(d.hashCode() == genericHash(d))
}
