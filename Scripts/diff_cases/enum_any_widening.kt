enum class Direction {
    NORTH,
    SOUTH,
    EAST,
    WEST,
}

enum class Color {
    RED,
    GREEN,
    BLUE,
}

fun takesAny(x: Any): Any = x

fun returnsAny(): Any = Direction.EAST

data class Wrapper(val value: Any)

fun main() {
    // BUG-179: widening an enum constant to Any must box it (tagged with its
    // declared name), not leak the raw ordinal Int.
    val x: Any = Direction.NORTH
    println(x)

    println(listOf(Direction.NORTH, Direction.SOUTH))

    println(takesAny(Direction.WEST))

    println(returnsAny())

    val w = Wrapper(Direction.SOUTH)
    println(w.value)
    println(w)

    // Two different enum classes erased to Any in the same collection.
    val mixed: List<Any> = listOf(Direction.NORTH, Color.RED, Direction.SOUTH, Color.BLUE)
    println(mixed)

    val ml = mutableListOf<Any>()
    ml.add(Direction.EAST)
    ml.add(Color.GREEN)
    println(ml)

    val nx: Any? = Direction.SOUTH
    println(nx)

    val p = Pair(Direction.NORTH, "hello")
    println(p)

    println(sequenceOf(Direction.NORTH, Direction.SOUTH).toList())

    // Direct (non-Any) enum comparisons and access must keep working.
    val d = Direction.NORTH
    println(d == Direction.NORTH)
    when (d) {
        Direction.NORTH -> println("is north")
        else -> println("not north")
    }
    val nd: Direction? = Direction.EAST
    println(nd)
    println(nd == Direction.EAST)
}
