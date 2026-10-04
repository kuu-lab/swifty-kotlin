// SKIP-DIFF (DEBT-DIFF-001): kotlin.system.getTimeNanos is a Kotlin/Native-only API not available in kotlinc.
import kotlin.system.getTimeNanos

fun main() {
    val t1 = getTimeNanos()
    val t2 = getTimeNanos()
    println(t1 > 0)
    println(t2 >= t1)
}
