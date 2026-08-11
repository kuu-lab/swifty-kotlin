// A statically enum-typed value renders as its entry name when interpolated or
// concatenated, not as the bare ordinal its KIR representation carries.
//
// This is the string-conversion counterpart to BUG-179's Any-boundary boxing:
// `val x: Any = Direction.SOUTH` boxes the ordinal together with its name, but
// a value that stays statically `Direction` never crosses that boundary and so
// reaches `kk_any_to_string` as a plain integer.
//
// `enum class`es carrying a constructor property (`enum class S(val code: Int)`)
// are deliberately absent: reading such a property does not link at all
// (BUG-188), independently of string conversion.
enum class Direction { NORTH, EAST, SOUTH, WEST }

fun describe(d: Direction): String = "heading $d"

fun main() {
    val d: Direction = Direction.SOUTH
    println("$d")
    println("dir=$d.")
    println("" + d)
    println(d.toString())
    println(describe(Direction.WEST))
    println("${Direction.NORTH} and ${Direction.EAST}")

    val nullable: Direction? = Direction.EAST
    println("$nullable")
    val absent: Direction? = null
    println("$absent")

    for (entry in Direction.entries) {
        println("entry $entry")
    }

    // Destructuring a tuple recovers the concrete element type, so the enum
    // component reaches string conversion statically typed rather than boxed.
    val (first, second) = Pair('p', Direction.NORTH)
    println("$first $second")
    val (a, b, c) = Triple(Direction.WEST, 1, Direction.EAST)
    println("$a $b $c")
}
