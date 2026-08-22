package golden.sema

// KSP-744: bundled kotlin.LazyThreadSafetyMode enum.
val sync = LazyThreadSafetyMode.SYNCHRONIZED
val pub = LazyThreadSafetyMode.PUBLICATION
val none = LazyThreadSafetyMode.NONE

fun main() {
    println(sync)
    println(pub)
    println(none)
}
