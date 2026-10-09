// KUU-1276: generic and overloaded constructors need an expected function type.
class Gen<T>(val x: T)

fun main() {
    val g: (Int) -> Gen<Int> = ::Gen
    println(g(5).x)
    val p: (Int, String) -> Pair<Int, String> = ::Pair
    println(p(1, "a").second)
    val t: (Int, Int, Int) -> Triple<Int, Int, Int> = ::Triple
    println(t(1, 2, 3).third)
    val e: (String) -> IllegalStateException = ::IllegalStateException
    println(e("m").message)
    val ia: (Int) -> IntArray = ::IntArray
    val values = ia(2)
    println(values.size)
    println(values[0])
    values[1] = 7
    println(values[1])
    val erased: Any = values
    println(erased is IntArray)
    println(erased is LongArray)
    try {
        ia(-1)
    } catch (e: NegativeArraySizeException) {
        println("negative size")
    }
}
