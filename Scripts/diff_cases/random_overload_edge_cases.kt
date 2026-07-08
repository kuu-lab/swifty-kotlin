import kotlin.random.Random

fun main() {
    val seeded1 = Random(99)
    val seeded2 = Random(99)

    println(seeded1.nextLong() == seeded2.nextLong())
    println(seeded1.nextFloat() == seeded2.nextFloat())

    val bytes1 = Random(5).nextBytes(ByteArray(4))
    val bytes2 = Random(5).nextBytes(ByteArray(4))
    println(bytes1.toList() == bytes2.toList())

    val r = Random(7)
    val longVal = r.nextLong(10L, 20L)
    // Written as 10L..19L rather than 10L until 20L: `Long.until` currently hits an
    // unrelated kswiftc runtime bug (KSWIFTK-RUNTIME-0001, kk_unbox_long called on a
    // non-LongBox object) when its LongRange result is used in a contains check.
    // See TODO.md DEBT-RT-007. 10L..19L is the same set of integers here.
    println(longVal in 10L..19L)
    // r.nextFloat(1.0f, 2.0f) case moved to random_nextfloat_ranged_synthetic.kt
    // (SKIP-DIFF): kotlin.random.Random has no ranged nextFloat overload on the JVM.
}
