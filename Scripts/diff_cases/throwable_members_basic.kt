fun main() {
    val root = Throwable("root")
    println(root.message)
    println(root.cause?.message)

    val wrapper = Throwable("wrapper", root)
    println(wrapper.message)
    println(wrapper.cause?.message)

    val late = Throwable("late")
    val returned = late.initCause(root)
    println(returned.message)
    println(late.cause?.message)

    val primary = RuntimeException("primary")
    println(primary.getSuppressed().size)
    println(primary.suppressedExceptions.size)

    primary.addSuppressed(IllegalStateException("first"))
    primary.addSuppressed(IllegalArgumentException("second"))
    println(primary.getSuppressed().size)

    val suppressed = primary.suppressedExceptions
    println(suppressed.size)
    println(suppressed[0].message)
    println(suppressed[1].message)

    try {
        throw IllegalStateException("thrown", root)
    } catch (e: Throwable) {
        println("caught: ${e.message} / ${e.cause?.message}")
    }
}
