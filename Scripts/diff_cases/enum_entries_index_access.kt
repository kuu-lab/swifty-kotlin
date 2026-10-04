import kotlin.enums.EnumEntries
import kotlin.enums.enumEntries

enum class Direction {
    NORTH,
    SOUTH,
    EAST,
    WEST,
}

fun main() {
    println(enumEntries<Direction>()[0])
    println(Direction.entries[1])
    println(Direction.entries.get(2))

    val entries: EnumEntries<Direction> = Direction.entries
    for (i in entries.indices) {
        println(entries[i])
    }

    println(entries[0] == Direction.NORTH)
    println(entries[3] == Direction.NORTH)
    println(enumValues<Direction>()[2] == Direction.entries[2])
}
