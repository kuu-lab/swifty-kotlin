// A `Pair`/`Triple` element keeps its concrete type when the tuple is printed
// through the generic `toString`. Two regressions this pins, both surfaced by
// KSP-608 moving the tuple bodies into bundled Kotlin source:
//
//  1. `__kk_pair_new` is a constructor bridged to an allocating runtime entry,
//     so it is called without the allocated-object argument an ordinary
//     `<init>` receives. ABI lowering used to shift every argument by that
//     phantom receiver and box each one against its neighbour's declared type,
//     leaving the first argument unboxed — a `Char` then printed as its code
//     point and an enum entry as its ordinal.
//  2. An inline stdlib function (`Map.plus`) that reads `pair.first` calls the
//     tuple's compiled property getter. The inline KIR body records that
//     callee's library link name, which the consumer must use verbatim when it
//     owns no symbol of its own for it.
enum class Direction { NORTH, SOUTH }

fun main() {
    println(Pair('a', 5))
    println(Pair(Direction.NORTH, "hello"))
    println(Triple('x', Direction.SOUTH, 'z'))

    // Element reads keep their static type, so they unbox back to Char/enum.
    val chars = Pair('k', 't')
    println(chars.first)
    println(chars.second)
    println(chars.toList())

    // Generic containers built from tuples keep the element types too.
    println(listOf("apple", "banana").associate { it.first() to it.length })
    println(listOf(Direction.NORTH, Direction.SOUTH).map { it to it.ordinal })

    // Inline stdlib functions reading `pair.first`/`pair.second`.
    val base: Map<Char, Int> = mapOf('a' to 1)
    println(base.plus('b' to 2))
    println(emptyMap<Char, Int>().plus('c' to 3))

    val (first, second) = Pair('p', Direction.NORTH)
    println("$first $second")
}
