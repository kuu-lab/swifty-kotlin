// DIFF_JVM
// Regression: JVM source grammar must accept an explicit getter return
// type (`val x get(): T ...`), which kotlinc uses for property type
// inference when the property has no type annotation.

class Holder {
    val block get(): Int {
        return 42
    }
    val expr get(): String = "hi"
    val nullable get(): Int? = null
    val typed: Long get(): Long = 7L
}

fun main() {
    val holder = Holder()
    println(holder.block)
    println(holder.expr)
    println(holder.nullable)
    println(holder.typed)
}
