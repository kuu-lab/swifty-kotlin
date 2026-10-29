// DIFF_JVM
// Mixed Int/Long floorDiv/mod folds follow Kotlin's result types (Long.mod(Int) is Int).
const val INT_MOD_LONG = 7.mod(-3L)
const val INT_FLOOR_DIV_LONG = 7.floorDiv(-3L)
const val LONG_MOD_INT = (-5L).mod(3)
const val LONG_MOD_INT_WRAPS = (5L.mod(3) + Int.MAX_VALUE).toLong()
const val LONG_FLOOR_DIV_INT = Long.MAX_VALUE.floorDiv(-1)

fun main() {
    println(INT_MOD_LONG)
    println(INT_FLOOR_DIV_LONG)
    println(LONG_MOD_INT)
    println(LONG_MOD_INT_WRAPS)
    println(LONG_FLOOR_DIV_INT)
    val y = 5L.mod(3)
    println(y + Int.MAX_VALUE)
}
