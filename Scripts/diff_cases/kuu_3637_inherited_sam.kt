// Nested fun interface inherited through a *class* stays constructible by
// simple name (KUU-3637 keeps class-inherited SAM construction working while
// rejecting the interface-inherited form, which is compile-only).
open class Base {
    fun interface Entry { fun get(): String }
}

class Child : Base() {
    fun value(): String = Entry { "sam" }.get()
}

fun main() {
    println(Child().value())
}
