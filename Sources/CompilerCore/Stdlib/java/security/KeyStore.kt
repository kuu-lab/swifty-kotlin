package java.security

import java.io.InputStream
import java.io.OutputStream
import java.security.cert.Certificate
import java.util.Collections
import java.util.Enumeration

public class KeyStore private constructor(
    public val type: String,
    public val provider: Provider,
) {
    private val entries = linkedMapOf<String, KeyEntry>()
    private var initialized = false

    public fun load(stream: InputStream?, password: CharArray?) {
        if (stream != null) {
            throw KeyStoreException("Loading serialized $type key stores is not supported")
        }
        entries.clear()
        initialized = true
    }

    public fun store(stream: OutputStream, password: CharArray?) {
        requireInitialized()
        throw KeyStoreException("Storing serialized $type key stores is not supported")
    }

    public fun getKey(alias: String, password: CharArray?): Key? {
        requireInitialized()
        val entry = entries[normalizeAlias(alias)] ?: return null
        val expected = entry.password
        if (expected != null && (password == null || !expected.contentEquals(password))) {
            throw UnrecoverableKeyException("Incorrect key password")
        }
        return entry.key
    }

    public fun setKeyEntry(
        alias: String,
        key: Key,
        password: CharArray?,
        certificateChain: Array<Certificate>,
    ) {
        requireInitialized()
        if (alias.isEmpty()) throw KeyStoreException("Alias must not be empty")
        if (key !is PrivateKey) throw KeyStoreException("Only private keys are supported")
        if (certificateChain.isEmpty()) throw KeyStoreException("Private key requires a certificate chain")
        entries[normalizeAlias(alias)] = KeyEntry(alias, key, password?.copyOf(), certificateChain.copyOf())
    }

    public fun aliases(): Enumeration<String> {
        requireInitialized()
        return Collections.enumeration(entries.values.map { it.alias })
    }

    public fun getCertificateChain(alias: String): Array<Certificate>? {
        requireInitialized()
        return entries[normalizeAlias(alias)]?.certificateChain?.copyOf()
    }

    public fun getCertificate(alias: String): Certificate? {
        requireInitialized()
        return entries[normalizeAlias(alias)]?.certificateChain?.firstOrNull()
    }

    public fun containsAlias(alias: String): Boolean {
        requireInitialized()
        return entries.containsKey(normalizeAlias(alias))
    }

    public fun size(): Int {
        requireInitialized()
        return entries.size
    }

    public fun isKeyEntry(alias: String): Boolean = containsAlias(alias)

    public fun deleteEntry(alias: String) {
        requireInitialized()
        entries.remove(normalizeAlias(alias))
    }

    private fun requireInitialized() {
        if (!initialized) throw IllegalStateException("KeyStore is not initialized")
    }

    private fun normalizeAlias(alias: String): String = alias.lowercase()

    public companion object {
        public fun getDefaultType(): String = "pkcs12"

        public fun getInstance(type: String): KeyStore {
            if (!type.equals("PKCS12", ignoreCase = true) && !type.equals("JKS", ignoreCase = true)) {
                throw KeyStoreException("$type KeyStore not available")
            }
            return KeyStore(type, bundledJcaProvider)
        }

        public fun getInstance(type: String, provider: String): KeyStore {
            if (!provider.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider)
            }
            return getInstance(type)
        }

        public fun getInstance(type: String, provider: Provider): KeyStore {
            if (!provider.name.equals(bundledJcaProvider.name, ignoreCase = true)) {
                throw NoSuchProviderException(provider.name)
            }
            return getInstance(type)
        }
    }
}

private class KeyEntry(
    val alias: String,
    val key: Key,
    val password: CharArray?,
    val certificateChain: Array<Certificate>,
)
