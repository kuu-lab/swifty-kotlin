import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ThreadLocalRandom
import kotlin.concurrent.thread

// KUU-3994: java.util.concurrent.ThreadLocalRandom. Values are entropy-seeded
// so nothing prints a raw random value — every assertion is a range/type or
// exception-contract check that kotlinc and kswiftc must agree on.
fun main() {
    val r = ThreadLocalRandom.current()

    // current() is stable within a thread and the class is a java.util.Random.
    println(ThreadLocalRandom.current() === ThreadLocalRandom.current()) // true
    val jr: java.util.Random = ThreadLocalRandom.current()
    println(jr.nextInt(10) in 0..9)                                     // true

    // nextInt family: bounds and rough uniformity.
    println(r.nextInt() is Int)
    var inRange = true
    var zeros = 0
    repeat(1000) {
        val v = r.nextInt(7)
        if (v !in 0..6) inRange = false
        if (v == 0) zeros++
    }
    println(inRange)          // true
    println(zeros in 80..220)  // true — ~1/7 of 1000, generous band

    var inRange2 = true
    repeat(500) {
        val v = r.nextInt(3, 9)
        if (v !in 3..8) inRange2 = false
    }
    println(inRange2)         // true

    val full = r.nextInt(Int.MIN_VALUE, Int.MAX_VALUE)
    println(full >= Int.MIN_VALUE && full < Int.MAX_VALUE)   // true

    // nextLong / nextDouble / nextFloat / nextBoolean / nextBytes / nextGaussian.
    var longsOk = true
    repeat(500) {
        val v = r.nextLong(1000)
        if (v !in 0L..999L) longsOk = false
        val w = r.nextLong(-50L, 50L)
        if (w !in -50L..49L) longsOk = false
    }
    println(longsOk)          // true
    println(r.nextLong() is Long)

    var dblOk = true
    repeat(500) {
        val v = r.nextDouble()
        if (!(v >= 0.0 && v < 1.0)) dblOk = false
        val w = r.nextDouble(2.5)
        if (!(w >= 0.0 && w < 2.5)) dblOk = false
        val x = r.nextDouble(-1.0, 1.0)
        if (!(x >= -1.0 && x < 1.0)) dblOk = false
    }
    println(dblOk)             // true

    var fltOk = true
    repeat(200) {
        val v = r.nextFloat()
        if (!(v >= 0f && v < 1f)) fltOk = false
    }
    println(fltOk)             // true
    println(r.nextBoolean() is Boolean)
    println(r.nextBoolean() is Boolean)
    val bytes = ByteArray(32)
    r.nextBytes(bytes)
    println(bytes.size)        // 32
    println(r.nextGaussian() is Double)

    // Exception contract (messages match java.util.Random's).
    try { r.nextInt(0); println("no-iae") } catch (e: IllegalArgumentException) { println("iae:" + e.message) }
    try { r.nextInt(-3); println("no-iae2") } catch (e: IllegalArgumentException) { println("iae2:" + e.message) }
    try { r.nextInt(5, 3); println("no-iae3") } catch (e: IllegalArgumentException) { println("iae3:" + e.message) }
    try { r.nextLong(0L); println("no-iae4") } catch (e: IllegalArgumentException) { println("iae4:" + e.message) }
    try { r.nextDouble(0.0); println("no-iae5") } catch (e: IllegalArgumentException) { println("iae5:" + e.message) }
    try { r.setSeed(42L); println("no-uoe") } catch (e: UnsupportedOperationException) { println("uoe") }

    // A worker thread gets a working per-thread instance too.
    val box = LinkedBlockingQueue<Boolean>()
    val t = thread {
        box.put(ThreadLocalRandom.current() === ThreadLocalRandom.current()) // true
        box.put(ThreadLocalRandom.current().nextInt(4) in 0..3)              // true
    }
    println(box.take())   // true
    println(box.take())   // true
    t.join()

    // Statistical sanity: nextInt(2) is roughly balanced (±20 sigma band).
    var heads = 0
    repeat(2000) { if (r.nextInt(2) == 0) heads++ }
    println(heads in 800..1200)   // true

    println("DONE")
}
