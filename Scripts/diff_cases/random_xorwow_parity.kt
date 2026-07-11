import kotlin.random.Random

// KSP-466: locks in bit-exact parity between KSwiftK's Kotlin-source XorWow
// implementation (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt) and
// kotlinc's own XorWowRandom for several fixed seeds. Unlike the other
// random_*.kt cases (which only assert range membership or seed-to-seed
// self-consistency), this prints raw generated values so diff_kotlinc.sh's
// stdout comparison against the real kotlinc reference fails immediately if
// the algorithm (state derivation, warm-up, or per-call bit manipulation)
// ever diverges from upstream, rather than only failing when a value happens
// to land outside an expected range.
fun printSequenceFor(seed: Int) {
    val r = Random(seed)
    println(r.nextInt())
    println(r.nextLong())
    println(r.nextBits(20))
    println(r.nextDouble())
    println(r.nextBoolean())
    println(r.nextInt(10, 15))
}

fun main() {
    for (seed in listOf(42, 0, -1, 123456789)) {
        printSequenceFor(seed)
    }

    val longSeeded = Random(123456789L)
    println(longSeeded.nextInt())
    println(longSeeded.nextLong())
}
