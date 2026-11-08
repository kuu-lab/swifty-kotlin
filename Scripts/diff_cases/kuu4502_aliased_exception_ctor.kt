// KUU-4502: `IllegalStateException` binds both the `kotlin` class and the
// `java.lang` typealias that aliases it (both are default imports), so the
// scope lookup yields two candidates for one nominal. The inferred getter
// must still publish its type for the earlier `throw sendException`.
class Derived : Base() {
    fun send(): String {
        try {
            throw sendException
        } catch (e: IllegalStateException) {
            return e.message ?: "none"
        }
    }
}

open class Base {
    protected val sendException get() = IllegalStateException("closed")
}

fun main() {
    println(Derived().send())
}
