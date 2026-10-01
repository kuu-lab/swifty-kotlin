// KUU-932: both operator and member calls on an interface-typed range must link.
fun check(range: ClosedRange<Int>): Boolean = 3 in range && range.contains(3)
fun checkNotIn(range: ClosedRange<Int>): Boolean = 7 !in range

fun main() {
    println(check(1..5))
    println(check(4..8))
    println(checkNotIn(1..5))
}
