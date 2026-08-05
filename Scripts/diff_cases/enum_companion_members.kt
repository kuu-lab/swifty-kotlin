enum class Direction {
    NORTH, SOUTH, EAST, WEST;

    companion object {
        val defaultLabel: String = "compass"
        fun count(): Int = 4
        fun opposite(direction: Direction): Direction = when (direction) {
            Direction.NORTH -> Direction.SOUTH
            Direction.SOUTH -> Direction.NORTH
            Direction.EAST -> Direction.WEST
            Direction.WEST -> Direction.EAST
        }
    }
}

fun main() {
    println(Direction.count())
    println(Direction.defaultLabel)
    println(Direction.opposite(Direction.NORTH))
    println(Direction.opposite(Direction.EAST))
    println(Direction.NORTH)
    println(Direction.values().size)
    println(Direction.valueOf("SOUTH"))
    println(Direction.entries)
}
