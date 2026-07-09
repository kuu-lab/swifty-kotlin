// SKIP-DIFF (DEBT-DIFF-005): Random(seed).nextBytes(array) currently hangs
// consuming real CPU (not a syspolicyd/Gatekeeper false hang — confirmed via
// `time`: ~90%+ CPU utilization, not near-0%). This is a regression from KSP-466
// (kotlin.random.Random's migration to Kotlin source, PR #4630), reproduces on a
// clean origin/master checkout with zero PR #4621 changes involved, and is
// tracked/being fixed as a separate, standalone bug rather than in PR #4621.
// Do NOT run with --force-run-skipped until that fix lands: it will hang the
// diff run rather than just fail it. Extracted from random_extended.kt and
// random_overload_edge_cases.kt, whose other (non-nextBytes) cases still run
// through the normal diff suite.
import kotlin.random.Random

fun main() {
    val r3 = Random(99)
    val r4 = Random(99)
    val bytes1 = r3.nextBytes(ByteArray(8))
    val bytes2 = r4.nextBytes(ByteArray(8))
    println("nextBytes size: ${bytes1.size}")
    println("nextBytes deterministic: ${bytes1.toList() == bytes2.toList()}")

    var bytesInRange = true
    val r5 = Random(123)
    val bigBytes = r5.nextBytes(ByteArray(200))
    for (b in bigBytes) {
        if (b < -128 || b > 127) {
            bytesInRange = false
        }
    }
    println("nextBytes in Byte range: $bytesInRange")

    val bytes3 = Random(5).nextBytes(ByteArray(4))
    val bytes4 = Random(5).nextBytes(ByteArray(4))
    println(bytes3.toList() == bytes4.toList())

    println("OK")
}
