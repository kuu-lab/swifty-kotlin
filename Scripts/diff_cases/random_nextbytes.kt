// Regression coverage for KSP-466: nextBytes(ByteArray) must preserve ByteArray typing and runtime storage.
import kotlin.random.Random

fun main() {
    // STDLIB-653: nextBytes fills a ByteArray with random bytes
    val r3 = Random(99)
    val r4 = Random(99)
    val bytes1 = r3.nextBytes(ByteArray(8))
    val bytes2 = r4.nextBytes(ByteArray(8))
    println("nextBytes size: ${bytes1.size}")
    println("nextBytes deterministic: ${bytes1.toList() == bytes2.toList()}")

    // Verify byte values are in Byte range [-128, 127]
    var bytesInRange = true
    val r5 = Random(123)
    val bigBytes = r5.nextBytes(ByteArray(200))
    for (b in bigBytes) {
        if (b < -128 || b > 127) {
            bytesInRange = false
        }
    }
    println("nextBytes in Byte range: $bytesInRange")
}
