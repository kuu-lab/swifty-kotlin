// BUG-164: callable reference used as an argument whose parameter type is a
// fun interface.  The lambda-literal equivalent already worked; the reference
// form must be SAM-converted too.
fun interface IntOp { fun apply(a: Int, b: Int): Int }

fun useOp(o: IntOp): Int = o.apply(10, 4)

fun myCompare(a: Int, b: Int): Int = a - b

fun main() {
    println(useOp(::myCompare))
}
