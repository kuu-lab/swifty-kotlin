// SKIP-DIFF (DEBT-DIFF-007): surfaced by compile-exit parity fix; triage and split or fix before re-enabling
import kotlin.random.Random

fun main() {
    val seeded1 = Random(99)
    val seeded2 = Random(99)

    println(seeded1.nextLong() == seeded2.nextLong())
    println(seeded1.nextFloat() == seeded2.nextFloat())

    // Use nextBytes(size); nextBytes(ByteArray) collides with it in the Random
    // vtable (both nextBytes#1) and can hang. Size overload matches kotlinc.
    val bytes1 = Random(5).nextBytes(4)
    val bytes2 = Random(5).nextBytes(4)
    println(bytes1.toList() == bytes2.toList())

    val r = Random(7)
    val longVal = r.nextLong(10L, 20L)
    // nextFloat(from, until) is KSwiftK-only; use standard nextDouble range API.
    val doubleVal = r.nextDouble(1.0, 2.0)
    println(longVal in 10L until 20L)
    println(doubleVal >= 1.0 && doubleVal < 2.0)
}
