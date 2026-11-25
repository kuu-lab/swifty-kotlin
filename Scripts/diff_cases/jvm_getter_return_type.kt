// DIFF_JVM
// Regression: JVM source grammar must accept an explicit getter return
// type (`val x get(): T ...`), which kotlinc uses for property type
// inference when the property has no type annotation.

@Target(AnnotationTarget.TYPE)
annotation class Mark(val value: Int)

class Holder {
    val block get(): Int {
        return 42
    }
    val expr get(): String = "hi"
    val nullable get(): Int? = null
    val typed: Long get(): Long = 7L
    // An `=` inside annotation arguments in the return type must not be
    // mistaken for the expression-body `=`.
    val annotated get(): @Mark(value = 7) Int {
        return 42
    }
}

fun main() {
    val holder = Holder()
    println(holder.block)
    println(holder.expr)
    println(holder.nullable)
    println(holder.typed)
    println(holder.annotated)
}
