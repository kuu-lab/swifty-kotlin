enum class Direction {
    NORTH,
    SOUTH,
}

fun main() {
    enumValues<Direction>().forEach { d -> println(d) }
    for (d in Direction.entries) {
        println(d)
    }
    println(enumValues<Direction>().toList())
    println(Direction.entries)

    val first = enumValues<Direction>()[0]
    val second = enumValues<Direction>()[1]
    println(first == Direction.NORTH)
    println(first == Direction.SOUTH)
    println(second == Direction.SOUTH)
    when (first) {
        Direction.NORTH -> println("first-is-north")
        Direction.SOUTH -> println("first-is-south")
    }
}
