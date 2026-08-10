enum class Direction { NORTH, SOUTH, EAST, WEST }

fun main() {
    // if-without-else reassignment
    var d1: Direction = Direction.NORTH
    if (1 > 0) { d1 = Direction.SOUTH }
    println(d1.name)
    println(d1.ordinal)

    // if/else reassignment (both branches)
    var d2: Direction = Direction.NORTH
    if (1 > 0) { d2 = Direction.EAST } else { d2 = Direction.WEST }
    println(d2.name)
    println(d2.ordinal)

    // reassignment inside a loop, final value after last iteration
    var d3: Direction = Direction.NORTH
    for (i in 1..3) {
        d3 = if (i % 2 == 0) Direction.SOUTH else Direction.EAST
    }
    println(d3.name)
    println(d3.ordinal)

    // multiple sequential reassignments with no branching
    var d4: Direction = Direction.NORTH
    d4 = Direction.SOUTH
    d4 = Direction.EAST
    d4 = Direction.WEST
    println(d4.name)
    println(d4.ordinal)

    // while-loop reassignment
    var d5: Direction = Direction.NORTH
    var i = 0
    while (i < 2) {
        d5 = Direction.WEST
        i++
    }
    println(d5.name)
    println(d5.ordinal)
}
