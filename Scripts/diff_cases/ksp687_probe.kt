fun main() {
    val ubytes = UByteArray(3) { (it + 1).toUByte() }
    println(ubytes.map { it.toString() })
}
