import kotlin.enums.enumEntries

enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    println(Direction.entries[0])
    println(Direction.entries[3])
    println(enumEntries<Direction>()[1])
    println(Direction.entries[0] == Direction.NORTH)
    println(Direction.entries[1] == Direction.SOUTH)
    println(Direction.entries[0] == Direction.SOUTH)
    println(enumValues<Direction>()[2] == Direction.EAST)
}
