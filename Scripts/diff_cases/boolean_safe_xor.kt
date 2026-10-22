// DIFF_JVM
fun main() {
    val t: Boolean? = true
    val f: Boolean? = false
    val n: Boolean? = null
    println(t?.xor(true))
    println(t?.xor(false))
    println(f?.xor(true))
    println(f?.xor(false))
    println(n?.xor(true))
    println(true.xor(true))
}
