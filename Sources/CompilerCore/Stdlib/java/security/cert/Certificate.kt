package java.security.cert

import java.io.Serializable
import java.security.PublicKey

public abstract class Certificate(public val type: String) : Serializable {
    public abstract val encoded: ByteArray
    public abstract val publicKey: PublicKey
}
