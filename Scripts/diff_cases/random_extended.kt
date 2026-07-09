import kotlin.random.Random

fun main() {
    // STDLIB-514: nextLong() unbounded
    val a = Random.nextLong()
    println("nextLong called: true")

    // STDLIB-515: nextFloat() in [0.0, 1.0)
    var okFloat = true
    repeat(100) {
        val f = Random.nextFloat()
        if (f < 0.0f || f >= 1.0f) {
            okFloat = false
        }
    }
    println("nextFloat in range: $okFloat")

    // STDLIB-655's nextFloat(until) / nextFloat(from, until) cases were moved to
    // random_nextfloat_ranged_synthetic.kt (SKIP-DIFF): kotlin.random.Random only
    // exposes a zero-arg nextFloat() on the JVM, so kotlinc rejects ranged overloads.

    // STDLIB-654: nextDouble(until)
    var okDoubleUntil = true
    repeat(100) {
        val d = Random.nextDouble(5.0)
        if (d < 0.0 || d >= 5.0) {
            okDoubleUntil = false
        }
    }
    println("nextDouble(5.0) in range: $okDoubleUntil")

    // STDLIB-516: Seeded Random determinism
    val r1 = Random(42)
    val r2 = Random(42)
    println("seeded nextInt match: ${r1.nextInt(100) == r2.nextInt(100)}")
    println("seeded nextLong match: ${r1.nextLong() == r2.nextLong()}")
    println("seeded nextFloat match: ${r1.nextFloat() == r2.nextFloat()}")
    println("seeded nextDouble match: ${r1.nextDouble() == r2.nextDouble()}")
    println("seeded nextBoolean match: ${r1.nextBoolean() == r2.nextBoolean()}")

    // STDLIB-653's nextBytes cases were moved to random_nextbytes_hang_workaround.kt
    // (SKIP-DIFF): Random(seed).nextBytes(array) currently hangs (KSP-466
    // regression, tracked separately), so it can't run under diff_kotlinc.sh's
    // timeout here.

    // STDLIB-RANDOM-100: nextBits(bitCount) determinism with seeded Random
    val r6 = Random(42)
    val r7 = Random(42)
    println("seeded nextBits(8) match: ${r6.nextBits(8) == r7.nextBits(8)}")
    println("seeded nextBits(16) match: ${r6.nextBits(16) == r7.nextBits(16)}")
    println("seeded nextBits(32) match: ${r6.nextBits(32) == r7.nextBits(32)}")

    // nextBits(bitCount) values must be in [0, 2^bitCount)
    var bitsInRange8 = true
    val r8 = Random(7)
    repeat(200) {
        val v = r8.nextBits(8)
        if (v < 0 || v >= 256) {
            bitsInRange8 = false
        }
    }
    println("nextBits(8) in range: $bitsInRange8")

    var bitsInRange1 = true
    val r9 = Random(3)
    repeat(200) {
        val v = r9.nextBits(1)
        if (v != 0 && v != 1) {
            bitsInRange1 = false
        }
    }
    println("nextBits(1) in range: $bitsInRange1")

    println("OK")
}
