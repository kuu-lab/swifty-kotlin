class A<out K> {
    fun foo(x: @UnsafeVariance K): K = x
}

fun test(a: A<*>): Any? = a.foo("OK")

fun box(): String = test(A<String>()) as String

fun main() {
    print(box())
}
