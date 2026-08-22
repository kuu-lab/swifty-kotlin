fun main() {
    val values = ULongArray(4) { (it + 1).toULong() }
    println(values.toList())
}
