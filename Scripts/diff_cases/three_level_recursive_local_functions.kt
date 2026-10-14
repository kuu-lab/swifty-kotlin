fun box(): String {
    var calls = 0
    fun foo(x) {
        fun bar(y) {
            fun baz(z) {
                calls++
                foo(z - 1)
            }
            baz(y)
        }
        if (x > 0) bar(x)
    }
    foo(3)
    return calls.toString()
}

fun main() {
    println(box())
}
