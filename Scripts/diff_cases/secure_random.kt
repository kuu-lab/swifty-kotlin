// SKIP-DIFF (DEBT-DIFF-005): SecureRandom.getInstance() with no arguments is a
// KSwiftK synthetic convenience factory (STDLIB-RANDOM-101). Real
// java.security.SecureRandom has no zero-arg getInstance() overload (it always
// requires an algorithm name), so kotlinc fails to resolve `sr`/`sr2`/`sr3` here
// and every subsequent member access cascades into "unresolved reference".
import java.security.SecureRandom

fun main() {
    // getInstance() returns a SecureRandom instance
    val sr = SecureRandom.getInstance()

    // nextBytes() fills a ByteArray with cryptographically secure random bytes
    val buf = ByteArray(8)
    sr.nextBytes(buf)
    println("nextBytes size: ${buf.size}")

    // generateSeed() returns a ByteArray of the requested length
    val seed = sr.generateSeed(4)
    println("generateSeed size: ${seed.size}")

    // setSeed() influences subsequent output when a seed is provided
    val sr2 = SecureRandom.getInstance()
    sr2.setSeed(42)
    val buf2a = ByteArray(4)
    sr2.nextBytes(buf2a)

    val sr3 = SecureRandom.getInstance()
    sr3.setSeed(42)
    val buf2b = ByteArray(4)
    sr3.nextBytes(buf2b)

    // Two instances with the same seed produce identical byte sequences
    println("seeded sequences match: ${buf2a.toList() == buf2b.toList()}")

    println("OK")
}
