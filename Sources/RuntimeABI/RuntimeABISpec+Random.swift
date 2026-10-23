// KSP-466: kotlin.random.Random's core API (nextInt/nextLong/nextFloat/
// nextDouble/nextBoolean/nextBits/nextBytes, Random.Default, Random(seed)) is
// now Kotlin source (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt) with
// no native ABI surface beyond __kk_random_seed_entropy. asKotlinRandom/
// asJavaRandom/java.util.Random are also real Kotlin source now (JavaUtilRandom.kt/
// PlatformRandom.kt) — a raw pointer passthrough between the two Random
// representations stopped being safe once kotlin.random.Random became a genuine
// compiled object instead of sharing java.util.Random's native SeededRandomBox.

private let abi = RuntimeABISectionBuilder("Random")

public extension RuntimeABISpec {
    static let randomFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_random_seed_entropy"),
        abi.th("__kk_random_nextInt_rangeObject", "receiver range outThrown"),
        abi.th("__kk_random_nextLong_rangeObject", "receiver range outThrown"),
        abi.th("__kk_random_nextULong_ulongRange", "receiver range outThrown"),
        abi.th("__kk_random_nextUInt_uintRange", "receiver range outThrown"),
        abi.nt("__kk_secure_random_get_instance"),
        abi.nt("__kk_secure_random_set_seed", "receiver seed"),
        abi.nt("__kk_secure_random_generate_seed", "receiver size"),
        abi.nt("__kk_secure_random_next_bytes", "receiver array"),
    ]
}
