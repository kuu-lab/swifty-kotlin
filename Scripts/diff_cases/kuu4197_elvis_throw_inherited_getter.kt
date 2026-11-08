class Derived : Base() {
    fun cancel(): String {
        try {
            throw closeCause ?: IllegalStateException("broadcast closed")
        } catch (e: Throwable) {
            return e.message ?: "null"
        }
    }
}

open class Base {
    private var cause: Any? = null
    protected val closeCause get() = cause as Throwable?
}

fun main() {
    println(Derived().cancel())
}
