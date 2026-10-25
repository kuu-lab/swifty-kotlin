// KUU-2914: virtual calls from a superclass initializer must dispatch to
// anonymous-object and local-class overrides that capture an enclosing mutable local.
abstract class WaitFor {
    init { condition() }
    abstract fun condition(): Boolean
}

fun main() {
    var result = "fail"
    val anonymous = object : WaitFor() {
        override fun condition(): Boolean { result = "anonymous"; return true }
    }
    println(result)

    result = "fail"
    class LocalWaitFor : WaitFor() {
        override fun condition(): Boolean { result = "local"; return true }
    }
    val local = LocalWaitFor()
    println(result)
}
