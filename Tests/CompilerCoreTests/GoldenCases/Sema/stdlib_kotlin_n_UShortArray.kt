package golden.sema

fun main() {
    val values = UShortArray(4) { (it + 1).toUShort() }
    println(values.toList())
}
