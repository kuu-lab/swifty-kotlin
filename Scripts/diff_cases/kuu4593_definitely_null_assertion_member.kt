// KUU-4593: Member accesses on a definitely-null `!!` receiver resolve
// against the asserted declared type and still throw NullPointerException.
class Box(val foo: Int) {
    fun bar(): Int = foo
}

fun main() {
    var b: Box? = Box(1)
    b = null
    try {
        println(b!!.foo)
    } catch (e: NullPointerException) {
        println("prop-npe")
    }

    var l: List<Int>? = listOf(1, 2, 3)
    l = null
    try {
        println(l!!.size)
    } catch (e: NullPointerException) {
        println("size-npe")
    }

    var c: Box? = Box(2)
    c = null
    try {
        println(c!!.bar())
    } catch (e: NullPointerException) {
        println("fun-npe")
    }
}
