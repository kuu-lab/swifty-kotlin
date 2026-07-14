// SKIP-DIFF (DEBT-DIFF-005): Random.nextBytes(ByteArray) is standard kotlin.random.Random API and
// kotlinc compiles/runs it fine, but kswiftc currently fails Sema resolution on the returned
// ByteArray ("Unresolved member function 'size'/'toList'"). Root cause appears to be the
// ByteArray RuntimeArrayBox/RuntimeListBox representation mismatch tracked under KSP-466/KSP-467
// (see Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRandomStubs.swift nextBytes stubs
// vs. the Kotlin-sourced Stdlib/kotlin/random/Random.kt). Split out of random_extended.kt
// (STDLIB-653) so the rest of the Random parity case can run; re-merge once the bug is fixed.
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
