package golden.sema

fun <T : Enum<T>> identity(value: T): T = value

enum class Direction { NORTH, SOUTH }

fun main() {
    println(Direction.NORTH is Enum<*>)
    println(Direction.NORTH is Comparable<*>)
    println(enumValues<Direction>().size)
    println(enumValueOf<Direction>("SOUTH"))
}
