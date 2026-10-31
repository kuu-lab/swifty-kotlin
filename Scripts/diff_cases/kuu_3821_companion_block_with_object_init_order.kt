// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3821: `companion {}` blocks and a `companion object` share one
// companion scope — all block property initializers run eagerly inside the
// same <clinit> before the companion object's own body, in declaration
// order relative to each other.

var initLog = ""
private fun init(tag: String, value: String): String { initLog += tag; return value }

class Mixed {
    companion { val beforeObject = init("A", "before") }
    companion object {
        val objectValue = init("B", "object")
        init { initLog += "I" }
    }
    companion { val afterObject = init("C", "after") }
}

fun main() {
    println(Mixed.objectValue)
    println(Mixed.beforeObject)
    println(Mixed.afterObject)
    println(initLog)
}
