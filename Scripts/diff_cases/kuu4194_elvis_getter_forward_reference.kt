class Derived : Base() {
    fun send(): String {
        try {
            throw sendException
        } catch (e: Throwable) {
            return e.message ?: "null"
        }
    }
}

open class Base {
    private var cause: Any? = null
    protected val closeCause get() = cause as Throwable?
    protected val sendException get() = closeCause ?: SendClosedException("closed")
}

class SendClosedException(message: String) : Exception(message)

fun main() {
    println(Derived().send())
}
