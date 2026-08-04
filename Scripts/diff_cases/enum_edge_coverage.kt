// SKIP-DIFF (BUG-173): printing a *collection* of raw enum values (here,
// `Direction.entries` and `enumValues<Direction>().toList()`) shows the
// ordinal instead of the name — kswiftc has no runtime type tag for enum
// values outside the specific call shapes EnumNameAccessLoweringPass rewrites
// at compile time. See TODO.md BUG-173 for the full root cause; unskip once
// fixed.
enum class Direction {
    NORTH,
    SOUTH,
}

fun main() {
    println(Direction.entries)
    println(enumValues<Direction>().toList())
    println(enumValueOf<Direction>("NORTH"))
    println(Direction.SOUTH.name)
    println(Direction.SOUTH.ordinal)

    try {
        println(enumValueOf<Direction>("WEST"))
    } catch (e: Throwable) {
        println("invalid-enum-name")
    }
}
