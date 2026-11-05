package java.util.concurrent

import java.lang.ThreadLocal
import kotlin.random.Random as KotlinRandom

// KUU-3994: java.util.concurrent.ThreadLocalRandom — the per-thread Random.
//
// `current()` hands each thread its own instance (stored in a java.lang
// ThreadLocal), so concurrent threads never share RNG state — the same
// contention-free contract the JDK class provides. Each instance is seeded
// once from the runtime entropy bridge and then draws every value through a
// private kotlin.random.Random (XorWow) delegate passed to the java.util.Random
// superclass constructor, which makes the whole inherited API surface —
// nextInt/nextLong/nextDouble/nextFloat/nextBoolean/nextBytes/nextGaussian —
// statistically sound without duplicating algorithms here. Like the JDK,
// sequences are seeded from entropy and are not reproducible across runs, and
// setSeed is rejected.
//
// JVM parity notes:
//  - ThreadLocalRandom extends java.util.Random on the JDK; the bundled
//    java.util.Random was made `open` for exactly this subclassing (its
//    nextBits routes to the wrapped Kotlin Random delegate).
//  - The JDK also exposes ints()/longs()/doubles() stream factories from the
//    Java 17 RandomGenerator interface; RandomGenerator does not exist in this
//    stdlib, so that surface is intentionally absent.
//  - The JDK's current() returns a singleton whose per-thread state lives in
//    hidden Thread fields, so `===` holds even across threads. Here each
//    thread gets its own instance object instead: `===` holds within a
//    thread but not across threads. The observable RNG contract — an
//    independent, contention-free sequence per thread — is identical, and
//    draws avoid a per-call ThreadLocal lookup that the singleton+fields
//    design would need.

// Same private bridge Random.kt uses for kotlin.random.Random.Default; the
// external name is the runtime symbol itself, so no @KsSymbolName is needed.
private external fun __kk_random_seed_entropy(): Long

public class ThreadLocalRandom private constructor(delegate: KotlinRandom) :
    java.util.Random(delegate) {

    public companion object {
        private val localRandom = object : ThreadLocal<ThreadLocalRandom>() {
            override fun initialValue(): ThreadLocalRandom =
                ThreadLocalRandom(KotlinRandom(__kk_random_seed_entropy()))
        }

        public fun current(): ThreadLocalRandom = localRandom.get()!!
    }

    override fun setSeed(seed: Long) {
        throw UnsupportedOperationException()
    }
}
