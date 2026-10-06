// SKIP-DIFF (DEBT-DIFF-001): kotlin.system.getTimeMillis is a Kotlin/Native-only API not available in kotlinc.
import kotlin.system.getTimeMillis

fun main() {
    val t1 = getTimeMillis()
    val t2 = getTimeMillis()
    println(t1 > 0)
    println(t2 >= t1)
}
