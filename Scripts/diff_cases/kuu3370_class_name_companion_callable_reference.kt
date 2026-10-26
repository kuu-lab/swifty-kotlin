// KUU-3370: A class-name reference to a companion member captures the companion.
open class A {
    fun instance() = true
    companion object : A() {
        fun companion() = true
    }
}
fun call(f: () -> Boolean) = f()
fun main() { println(call(A::companion)) }
