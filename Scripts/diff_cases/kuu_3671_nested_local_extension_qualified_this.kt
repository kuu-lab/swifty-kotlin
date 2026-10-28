// EXPECT-STDOUT: OK 42 0
// EXPECT-STDOUT: outer-7-mid
// KUU-3671: a labeled `this@outer` inside nested local extension functions
// must reach the outermost extension receiver through each enclosing local
// function's capture environment (JetBrains extensionFunctions/kt5467.kt).
fun String.foo(): String {
    fun Int.bar(): String {
        fun Long.baz(): String {
            return "${this@foo} ${this@bar} ${this@baz}"
        }
        return 0L.baz()
    }
    return 42.bar()
}

// Two levels: the inner local extension reads the enclosing extension
// receiver by label even though the enclosing body does not itself.
fun outermost(): String {
    fun String.mid(): String {
        fun Int.inner(): String = "${this@mid}-${this@inner}-mid"
        return 7.inner()
    }
    return "outer".mid()
}

fun main() {
    println("OK".foo())
    println(outermost())
}
