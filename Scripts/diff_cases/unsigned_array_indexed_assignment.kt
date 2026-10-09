@OptIn(ExperimentalUnsignedTypes::class)
fun main() {
    val a = ubyteArrayOf(0u)
    a[0] = 255u
    println(a[0])
    a[0] = 0u
    println(a[0])

    val shorts = ushortArrayOf(0u)
    shorts[0] = 65535u
    println(shorts[0])
    shorts[0] = 0u
    println(shorts[0])
}
