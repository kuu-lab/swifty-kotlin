// A nested classifier inherited through a *class* still exposes its
// companion's invoke by simple name (KUU-3636 rejects only the
// interface-inherited form, which is compile-only).
open class Base {
    interface Entry {
        companion object { operator fun invoke(text: String): String = "invoke:" + text }
    }
}

class Child : Base() {
    fun value(): String = Entry("inner")
}

fun main() {
    println(Child().value())
}
