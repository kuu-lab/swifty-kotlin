// DIFF_LINE_PATTERN: Plain@[0-9a-f]+
// KUU-4455: println/print on a singleton object without its own toString()
// must render the JVM default Any.toString() identity `Name@hash`, not the
// bare simple name. Objects with an own (declared or synthesized) toString()
// still print through it.
object Plain
object Custom {
    override fun toString(): String = "custom-tostring"
}
data object Settings
open class Code(val x: String) { override fun toString() = x }
object K : Code("K")
object K2 : Code("different-name")

fun main() {
    println(Plain)
    val p = Plain
    println(p)
    println(Custom)
    println(Settings)
    println(K)
    println(K2)
    val a: Any = Plain
    println(a)
    println(Plain.toString())
    print(Plain)
    println()
}
