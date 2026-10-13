import kotlin.reflect.*

fun sum(vararg values: Long): Long = values.sum()

fun main() {
    val params = ::sum.parameters
    for (p in params) println("${p.name}:${p.type}:${p.isVararg}")
}
