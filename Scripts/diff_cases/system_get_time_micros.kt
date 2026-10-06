// SKIP-DIFF (DEBT-DIFF-001): kotlin.system.getTimeMicros is a Kotlin/Native-only API not available in kotlinc.
import kotlin.system.getTimeMicros

fun main() {
    val t1 = getTimeMicros()
    val t2 = getTimeMicros()
    println(t1 > 0)
    println(t2 >= t1)
}
