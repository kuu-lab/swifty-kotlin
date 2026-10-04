fun main() {
    val values = UIntArray(4) { (it + 1).toUInt() }
    println(values.size)
    println(values[0])
    println(values[3])
    println(UIntArray(0) { 42u }.size)
}
