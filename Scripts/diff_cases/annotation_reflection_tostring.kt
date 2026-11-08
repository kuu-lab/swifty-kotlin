// KUU-4386: annotation instances materialized through reflection quote
// String/Char members like the JVM proxy toString, while directly
// constructed instances keep the bare kotlinc-style rendering.
annotation class Note(val v: String = "d")
annotation class Mark(val c: Char)
annotation class Pair2(val a: Int = 7, val z: String = "d")

@Note("x") @Mark('q') @Pair2(z = "hi") class Target

fun main() {
    for (a in Target::class.annotations) println(a)
    println(Note("y"))
    println(Mark('w'))
    println(Pair2())
}
