package kotlin.random

import kotlin.internal.KsSymbolName

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
