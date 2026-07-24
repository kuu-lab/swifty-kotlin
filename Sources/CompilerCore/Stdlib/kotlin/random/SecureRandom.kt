package kotlin.random

import kotlin.internal.KsSymbolName

// KSP-467: SecureRandom compatibility layer migrated to bundled Kotlin source.
// The public surface is a class that delegates to the runtime's __kk_secure_random_*
// bridges. The runtime opaque handle is passed as `this` to the member bridges.

public class SecureRandom private constructor() {
    public companion object {
        @KsSymbolName("__kk_secure_random_get_instance")
        public external fun getInstance(): SecureRandom
    }

    @KsSymbolName("__kk_secure_random_set_seed")
    public external fun setSeed(seed: Int)

    @KsSymbolName("__kk_secure_random_generate_seed")
    public external fun generateSeed(size: Int): ByteArray

    @KsSymbolName("__kk_secure_random_next_bytes")
    public external fun nextBytes(array: ByteArray)
}
