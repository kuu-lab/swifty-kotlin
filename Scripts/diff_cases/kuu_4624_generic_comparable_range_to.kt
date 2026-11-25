// DIFF_JVM
// KUU-4624: Kotest's generic Comparable matcher checks `value in lower..upper`.
fun <T : Comparable<T>> between(value: T, lower: T, upper: T): Boolean = value in lower..upper

fun <T : Comparable<T>> betweenViaRange(value: T, lower: T, upper: T): Boolean {
    val range = lower..upper
    return value in range
}

fun main() {
    println(between("b", "a", "c"))
    println(between("d", "a", "c"))
    println(between(2, 1, 3))
    println(between(4, 1, 3))
    println(betweenViaRange("b", "a", "c"))
    println(betweenViaRange("d", "a", "c"))
    println(betweenViaRange(2, 1, 3))
    println(betweenViaRange(4, 1, 3))
}
