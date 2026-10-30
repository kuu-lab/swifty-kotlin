import java.security.MessageDigest

fun main() {
    println(booleanArrayOf(true, false).joinToString(",") { if (it) "T" else "F" })
    println(byteArrayOf(9, -113).joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') })
    println(shortArrayOf(-2, 1).joinToString(",") { (it + 1).toString() })
    println(intArrayOf(1, 2).joinToString(",") { (it + 1).toString() })
    println(doubleArrayOf(1.5, -0.0).joinToString(",") { it.toString() })
    println(listOf<Byte?>(null, -1, 1).joinToString(",") { it?.toString() ?: "null" })
    val digest = MessageDigest.getInstance("MD5").digest("test".encodeToByteArray())
    println(digest.joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') })
    @Suppress("UNCHECKED_CAST")
    val wrong = listOf<Any>("wrong") as List<Boolean>
    try { println(wrong.joinToString { if (it) "T" else "F" }) }
    catch (e: ClassCastException) { println("wrong type") }
}
