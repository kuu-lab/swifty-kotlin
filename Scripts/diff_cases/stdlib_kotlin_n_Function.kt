// KSP-740: kotlin.Function base interface resolution diff case

fun main() {
    val f: kotlin.Function<Int>? = null
    if (f == null) {
        println("null")
    } else {
        println("not null")
    }
}
