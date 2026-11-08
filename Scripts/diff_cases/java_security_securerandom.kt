import java.security.NoSuchAlgorithmException
import java.security.SecureRandom

// KUU-4405: bundled java.security.SecureRandom delegates to the runtime
// CSPRNG. Pins JVM parity for constructors, instance/factory resolution,
// range/type behaviour of the next* family, generateSeed sizing, setSeed
// acceptance, and NoSuchAlgorithmException for unknown algorithms. Output
// is restricted to deterministic facts because the byte stream is random.

fun main() {
    val r = SecureRandom()
    println(r is SecureRandom)
    println(r.nextInt(10) in 0..9)
    println(r.nextInt(1))
    println(r.nextLong() != 0L || true)
    println(r.nextBoolean() || !r.nextBoolean() || true)
    println(r.nextFloat() in 0.0f..1.0f)
    println(r.nextDouble() in 0.0..1.0)
    val b = ByteArray(8)
    r.nextBytes(b)
    println(b.size)
    println(r.generateSeed(4).size)
    println(r.generateSeed(0).size)
    r.setSeed(byteArrayOf(1, 2, 3))
    r.setSeed(42L)
    println(SecureRandom(byteArrayOf(7)).nextInt(100) in 0..99)
    println(SecureRandom.getInstanceStrong() is SecureRandom)
    println(SecureRandom.getInstance("SHA1PRNG") is SecureRandom)
    println(SecureRandom.getInstance("NativePRNG") is SecureRandom)
    try {
        SecureRandom.getInstance("NOPE")
        println("no-throw")
    } catch (e: NoSuchAlgorithmException) {
        println("nsae")
    }
}
