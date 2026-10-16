fun box(): String {
    var calls = 0
    fun foo(x: Int) {
        fun bar(y: Int) {
            fun baz(z: Int) {
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
