// DIFF_JVM
import java.math.BigDecimal
import kotlin.text.toBigDecimal as parseDecimal

fun String.toBigDecimal(): BigDecimal = BigDecimal("7")

fun main() {
    println("1.5".parseDecimal().toString())
    println("42".toBigDecimal().toString())
    val reference: (String) -> BigDecimal = String::parseDecimal
    println(reference("1.4").toString())
}
