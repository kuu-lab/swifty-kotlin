class Outer {
    enum class Direction { NORTH, SOUTH, EAST, WEST }
}

fun main() {
    // name/ordinal: synthetic properties on the nested enum class itself.
    println(Outer.Direction.NORTH.name)
    println(Outer.Direction.NORTH.ordinal)

    // EnumClass.values(): static factory returning Array<T>, resolved
    // directly on the enum class (not the companion).
    val values = Outer.Direction.values()
    println(values.size)

    // EnumClass.entries: EnumEntries<T> is a read-only List<T>-subtype;
    // its List members (.size, forEach iteration) must resolve and run.
    val entries = Outer.Direction.entries
    println(entries.size)

    var count = 0
    entries.forEach { count++ }
    println(count)
}
