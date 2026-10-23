// KUU-3023: a local extension function on an interface receiver resolves
// through the lexical function-value path when invoked on a variable of the
// interface type.
interface Src {
    val size: Long
}

class Data(override val size: Long) : Src

fun topLevel(s: Src) {
    fun Src.helper2(): Long = size
    println(s.helper2())
}

fun main() {
    topLevel(Data(7))
}
