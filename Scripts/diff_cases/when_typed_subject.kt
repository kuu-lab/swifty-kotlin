fun nullableInput(): Int? = 7

fun main() {
    println(when (val missing: Int? = null) {
        null -> "literal"
        else -> "other"
    })
    println(when (val value: Int? = nullableInput()) {
        null -> 0
        else -> value + 1
    })
    println(when (val value: Long = 42) { else -> value })
    println(when (val value: Any = 42L) {
        is Long -> value + 1L
        else -> 0L
    })
    println(when (val value: Long? = Long.MIN_VALUE) {
        null -> "null"
        else -> "present"
    })
    println(when (val items: List<Int> = emptyList()) { else -> items.size })
    println(when (val action: (Int) -> Int = { it + 1 }) { else -> action(2) })
    println(when (val action: (Int) -> Int = { it + 1 }) {
        is (Int) -> Int -> action(2)
        else -> 0
    })
    println(when (val items: List<Int> = emptyList()) {
        is List<*> -> items.size
        else -> -1
    })
    println(when (val value: Long = 42) {
        in 40L..45L -> value
        else -> 0L
    })
    println(when (val value = 3) { else -> value })
}
