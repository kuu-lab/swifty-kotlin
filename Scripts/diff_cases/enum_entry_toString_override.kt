// BUG-A: `toString()` overridden in an enum entry body (and, separately, at
// the enum class level) must be honored by every Any-erased rendering path
// (println, string interpolation, values()/entries elements) -- not just the
// default $enumOrdinalToName bare-name rendering.
enum class Op(val sym: String) {
    ADD("+") { override fun apply(a: Int, b: Int) = a + b },
    SUB("-") { override fun apply(a: Int, b: Int) = a - b },
    MUL("*") { override fun apply(a: Int, b: Int) = a * b; override fun toString() = "times" };
    abstract fun apply(a: Int, b: Int): Int
}

enum class Planet { MERCURY, VENUS; override fun toString() = "planet-" + name.lowercase() }

fun main() {
    println(Op.MUL)
    println("${Op.MUL}")
    println(Op.MUL.name)
    println(Op.SUB)
    println(Op.entries.map { it.apply(6, 2) })
    println(Op.entries)

    println(Planet.VENUS)
    println("${Planet.MERCURY}")
    println(Planet.MERCURY.name)
    println(listOf(Planet.VENUS))
}
