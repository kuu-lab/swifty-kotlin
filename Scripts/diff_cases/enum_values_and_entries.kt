enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    // EnumClass.values(): static factory returning Array<T>, resolved
    // directly on the enum class (not the companion).
    val values = Direction.values()
    println(values.size)

    // EnumClass.entries: EnumEntries<T> is a read-only List<T>-subtype;
    // its List members (.size, forEach iteration) must resolve and run.
    val entries = Direction.entries
    println(entries.size)

    var count = 0
    entries.forEach { count++ }
    println(count)
}
