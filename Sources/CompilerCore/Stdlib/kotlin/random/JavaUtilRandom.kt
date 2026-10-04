package java.util

import kotlin.random.Random as KotlinRandom

// KSP-466: java.util.Random used to share its native SeededRandomBox
// representation with kotlin.random.Random, so asKotlinRandom()/asJavaRandom()
// could just pass the same opaque handle straight through. Now that
// kotlin.random.Random is a genuine compiled Kotlin object (see
// kotlin.random.Random in Random.kt), a raw pointer passthrough between the two
// is no longer safe: calling a Random method on a handle that is actually a
// SeededRandomBox reads through the wrong object layout. This class instead
// wraps a real kotlin.random.Random so the conversion is a genuine field access.
// (Aliased as KotlinRandom here since this class is itself named Random.)
//
// Only enough surface exists here to keep that conversion safe. The rest of
// java.util.Random's own API (nextInt/nextDouble/etc. as members of this class)
// remains KSP-467 scope.
public class Random {
    public val delegate: KotlinRandom

    // NOTE: these deliberately assign `delegate` in the constructor body rather
    // than delegating via `: this(KotlinRandom(seed))`. Constructor delegation
    // syntax resolves `KotlinRandom(seed)` back to *this* class's own
    // constructor instead of the aliased kotlin.random.Random — since both
    // classes are named "Random", this causes infinite recursion (confirmed via
    // `sample` on the hung process: identical compiled frame calling itself).
    // Plain expression position (as used below) resolves the alias correctly.
    // This looks like a general compiler bug in constructor-delegation-argument
    // resolution, not specific to Random; flagged separately for a proper fix.
    public constructor(seed: Int) {
        delegate = KotlinRandom(seed)
    }

    public constructor(seed: Long) {
        delegate = KotlinRandom(seed)
    }

    public constructor(delegate: KotlinRandom) {
        this.delegate = delegate
    }
}
