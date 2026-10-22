import java.util.Random
import kotlin.random.asJavaRandom
import kotlin.random.asKotlinRandom

// KUU-2780: java.util.Random no-arg ctor and instance methods. Seeded values
// follow the JDK's 48-bit LCG, so they byte-compare against kotlinc.
// (nextGaussian is intentionally omitted: it goes through StrictMath.log, which
// can differ from libm by one ulp.)
fun main() {
    println(Random().nextInt(100) in 0..99)
    println(Random().nextDouble() in 0.0..1.0)

    val r = Random(42)
    println(r.nextInt(100))
    println(r.nextInt(100))
    println(r.nextInt())
    println(Random(42L).nextLong())
    println(Random(42).nextDouble())
    println(Random(42).nextFloat())
    println(Random(42).nextBoolean())
    println(Random(42).nextInt(5, 10))
    println(Random(42).nextLong(1000L))
    println(Random(42).nextDouble(10.0))

    val bytes = ByteArray(6)
    Random(42).nextBytes(bytes)
    println(bytes.toList())

    val reseeded = Random(1)
    reseeded.setSeed(42)
    println(reseeded.nextInt())

    println(Random(42).asKotlinRandom().nextInt())
    println(kotlin.random.Random(7).asJavaRandom().nextInt(10) in 0..9)

    try {
        Random().nextInt(0)
    } catch (e: IllegalArgumentException) {
        println(e.message)
    }
}
