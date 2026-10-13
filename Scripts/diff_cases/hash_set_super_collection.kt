// KUU-1946: superclass construction must initialize the existing subclass object.
class CopySet : HashSet<Int>(listOf(1, 2))
fun main() {
    val values = CopySet()
    println(values.size)
    println(values.contains(1))
    println(values.contains(2))
}
