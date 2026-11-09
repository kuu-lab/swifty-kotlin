package java.security

import kotlin.internal.KsSymbolName

public class KeyPairGenerator private constructor(
    public val algorithm: String,
    public val provider: Provider,
) {
    private var keySize = 2048

    public fun initialize(keySize: Int) {
        validateKeySize(keySize)
        this.keySize = keySize
    }

    public fun initialize(keySize: Int, random: SecureRandom) {
        validateKeySize(keySize)
        this.keySize = keySize
    }

    public fun generateKeyPair(): KeyPair {
        val privateEncoding = ByteArray(8192)
        val publicEncoding = ByteArray(8192)
        val lengths = generateRSAKeyPair(keySize, privateEncoding, publicEncoding)
        if (lengths < 0L) {
            throw ProviderException("RSA key generation is unavailable in this runtime")
        }
        val privateLength = lengths.toInt()
        val publicLength = (lengths ushr 32).toInt()
        if (privateLength <= 0 || publicLength <= 0 || privateLength > privateEncoding.size || publicLength > publicEncoding.size) {
            throw ProviderException("RSA key generation returned invalid key data")
        }
        val privateKey = EncodedPrivateKey(algorithm, privateEncoding.copyOf(privateLength))
        val publicKey = EncodedPublicKey(algorithm, publicEncoding.copyOf(publicLength))
        return KeyPair(publicKey, privateKey)
    }

    private fun validateKeySize(value: Int) {
        if (value < 512 || value > 16384 || value % 64 != 0) {
            throw InvalidParameterException("RSA key size must be a multiple of 64 between 512 and 16384 bits")
        }
    }

    public companion object {
        public fun getInstance(algorithm: String): KeyPairGenerator {
            if (!algorithm.equals("RSA", ignoreCase = true)) {
                throw NoSuchAlgorithmException("$algorithm KeyPairGenerator not available")
            }
            return KeyPairGenerator("RSA", bundledJcaProvider)
        }

        public fun getInstance(algorithm: String, provider: String): KeyPairGenerator {
            if (!provider.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider)
            }
            return getInstance(algorithm)
        }

        public fun getInstance(algorithm: String, provider: Provider): KeyPairGenerator {
            if (!provider.name.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider.name)
            }
            return getInstance(algorithm)
        }
    }
}

@KsSymbolName("__kk_security_rsa_generate_key_pair")
private external fun generateRSAKeyPair(keySize: Int, privateOutput: ByteArray, publicOutput: ByteArray): Long
