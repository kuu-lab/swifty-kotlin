package java.security

import kotlin.internal.KsSymbolName

public class Signature private constructor(
    public val algorithm: String,
    private val normalizedAlgorithm: String,
    public val provider: Provider,
) {
    private var signingKey: PrivateKey? = null
    private var verifyingKey: PublicKey? = null
    private var input = ByteArray(0)

    public fun initSign(privateKey: PrivateKey) {
        if (!privateKey.algorithm.equals("RSA", ignoreCase = true) || privateKey.encoded == null) {
            throw InvalidKeyException("RSA private key required")
        }
        signingKey = privateKey
        verifyingKey = null
        input = ByteArray(0)
    }

    public fun initSign(privateKey: PrivateKey, random: SecureRandom) {
        initSign(privateKey)
    }

    public fun initVerify(publicKey: PublicKey) {
        if (!publicKey.algorithm.equals("RSA", ignoreCase = true) || publicKey.encoded == null) {
            throw InvalidKeyException("RSA public key required")
        }
        verifyingKey = publicKey
        signingKey = null
        input = ByteArray(0)
    }

    public fun update(value: Byte) {
        append(byteArrayOf(value))
    }

    public fun update(data: ByteArray) {
        update(data, 0, data.size)
    }

    public fun update(data: ByteArray, offset: Int, length: Int) {
        if (signingKey == null && verifyingKey == null) {
            throw SignatureException("Signature is not initialized")
        }
        if (data.size - offset < length) throw IllegalArgumentException("Input buffer too short")
        if (offset < 0 || length < 0 || offset > data.size - length) throw ArrayIndexOutOfBoundsException()
        if (length == 0) return
        append(data.copyOfRange(offset, offset + length))
    }

    public fun sign(): ByteArray {
        val key = signingKey ?: throw SignatureException("Signature is not initialized for signing")
        val encodedKey = key.encoded ?: throw InvalidKeyException("Private key has no encoding")
        val result = ByteArray(16384)
        val length = securitySign(normalizedAlgorithm, encodedKey, input, result)
        input = ByteArray(0)
        if (length <= 0 || length > result.size) throw SignatureException("RSA signing failed")
        return result.copyOf(length)
    }

    public fun verify(signature: ByteArray): Boolean {
        val key = verifyingKey ?: throw SignatureException("Signature is not initialized for verification")
        val encodedKey = key.encoded ?: throw InvalidKeyException("Public key has no encoding")
        val result = securityVerify(normalizedAlgorithm, encodedKey, input, signature)
        input = ByteArray(0)
        return when (result) {
            1 -> true
            0 -> false
            else -> throw SignatureException("RSA verification failed")
        }
    }

    public fun reset() {
        input = ByteArray(0)
    }

    private fun append(bytes: ByteArray) {
        if (signingKey == null && verifyingKey == null) {
            throw SignatureException("Signature is not initialized")
        }
        val combined = ByteArray(input.size + bytes.size)
        input.copyInto(combined)
        bytes.copyInto(combined, input.size)
        input = combined
    }

    public companion object {
        public fun getInstance(algorithm: String): Signature {
            val normalized = normalizeSignatureAlgorithm(algorithm)
            if (normalized !in supportedSignatureAlgorithms) {
                throw NoSuchAlgorithmException("$algorithm Signature not available")
            }
            return Signature(algorithm, normalized, bundledJcaProvider)
        }

        public fun getInstance(algorithm: String, provider: String): Signature {
            if (!provider.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider)
            }
            return getInstance(algorithm)
        }

        public fun getInstance(algorithm: String, provider: Provider): Signature {
            if (!provider.name.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider.name)
            }
            return getInstance(algorithm)
        }
    }
}

private val supportedSignatureAlgorithms = setOf(
    "SHA1WITHRSA",
    "SHA256WITHRSA",
    "SHA384WITHRSA",
    "SHA512WITHRSA",
)

private fun normalizeSignatureAlgorithm(value: String): String =
    value.uppercase().replace("-", "").replace("_", "").replace(" ", "")

@KsSymbolName("__kk_security_rsa_sign")
private external fun securitySign(algorithm: String, privateKey: ByteArray, data: ByteArray, output: ByteArray): Int

@KsSymbolName("__kk_security_rsa_verify")
private external fun securityVerify(algorithm: String, publicKey: ByteArray, data: ByteArray, signature: ByteArray): Int
