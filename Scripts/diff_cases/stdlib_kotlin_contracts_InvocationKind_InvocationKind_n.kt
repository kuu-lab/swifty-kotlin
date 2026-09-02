import kotlin.contracts.ExperimentalContracts
import kotlin.contracts.InvocationKind

@OptIn(ExperimentalContracts::class)
fun main() {
    val entries1 = InvocationKind.entries
    val entries2 = InvocationKind.entries
    println(entries1.size)
    println(entries1[0])
    println(entries1[1])
    println(entries1[2])
    println(entries1[3])
    println(entries1 === entries2)

    val values1 = InvocationKind.values()
    val values2 = InvocationKind.values()
    println(values1.size)
    println(values1[0])
    println(values1[1])
    println(values1[2])
    println(values1[3])
    println(values1 === values2)

    println(InvocationKind.valueOf("EXACTLY_ONCE"))
    try {
        InvocationKind.valueOf("missing")
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
