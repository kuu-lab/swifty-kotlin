fun main() {
    val values = UShortArray(4) { (it + 1).toUShort() }
    println(values.size)
    println(values[0])
    println(values[3])
    println(UShortArray(0) { 42.toUShort() }.size)
}
