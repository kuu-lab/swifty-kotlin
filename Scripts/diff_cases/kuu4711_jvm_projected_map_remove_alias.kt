// DIFF_JVM
import kotlin.collections.remove as removeProjected

fun main() {
    val projected: MutableMap<out Int, String> = mutableMapOf(6 to "w")
    println(projected.removeProjected(6))
    println(projected.removeProjected(6))
}
