package java.security

import java.io.Serializable

public interface Key : Serializable {
    public val algorithm: String
    public val format: String?
    public val encoded: ByteArray?
}

public interface PrivateKey : Key

public interface PublicKey : Key

public class KeyPair(
    private val publicKey: PublicKey,
    private val privateKey: PrivateKey,
) : Serializable {
    public fun getPublic(): PublicKey = publicKey

    public fun getPrivate(): PrivateKey = privateKey
}

internal class EncodedPrivateKey(
    override val algorithm: String,
    override val encoded: ByteArray,
) : PrivateKey {
    override val format: String = "PKCS#8"
}

internal class EncodedPublicKey(
    override val algorithm: String,
    override val encoded: ByteArray,
) : PublicKey {
    override val format: String = "X.509"
}

public interface SecureRandomParameters
