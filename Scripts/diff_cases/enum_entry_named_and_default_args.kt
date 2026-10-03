// Named entry arguments bind by label, and defaults may refer to earlier
// constructor parameters.
enum class C(val r: Int, val g: Int, val b: Int = r + 1) { X(g = 1, r = 2), Y(5, 6), Z(b = 9, g = 8, r = 7) }

enum class Label(val text: String, val upper: String = text.uppercase()) { HI("hi"), BYE("bye", "Bye!") }

fun main() {
    for (c in C.entries) println("${c.name} ${c.r} ${c.g} ${c.b}")
    println(Label.HI.upper)
    println(Label.BYE.upper)
}
