package java.security

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream
import java.io.InputStream
import java.io.OutputStream
import java.security.cert.Certificate
import java.util.Collections
import java.util.Enumeration
import kotlin.internal.KsSymbolName

public class KeyStore private constructor(
    public val type: String,
    public val provider: Provider,
) {
    private val entries = linkedMapOf<String, KeyEntry>()
    private var initialized = false

    public fun load(stream: InputStream?, password: CharArray?) {
        if (stream == null) {
            entries.clear()
            initialized = true
            return
        }

        requirePKCS12()
        val encodedStore = readBounded(stream)
        val imported = ByteArray(minOf(MAX_KEYSTORE_BYTES, encodedStore.size * 2 + 8192))
        val importedLength = loadPKCS12(encodedStore, password?.concatToString() ?: "", imported)
        if (importedLength <= 0 || importedLength > imported.size) {
            throw KeyStoreException("Could not load PKCS12 KeyStore")
        }

        val parsedEntries = linkedMapOf<String, KeyEntry>()
        try {
            val input = DataInputStream(ByteArrayInputStream(imported.copyOf(importedLength)))
            if (input.readInt() != KEYSTORE_WIRE_MAGIC || input.readInt() != KEYSTORE_WIRE_VERSION) {
                throw KeyStoreException("Invalid PKCS12 KeyStore data")
            }
            val entryCount = input.readInt()
            if (entryCount < 0 || entryCount > MAX_KEYSTORE_ENTRIES) {
                throw KeyStoreException("Invalid PKCS12 entry count")
            }
            repeat(entryCount) {
                val alias = input.readField(MAX_ALIAS_BYTES).decodeToString()
                if (alias.isEmpty()) throw KeyStoreException("Invalid empty PKCS12 alias")
                val privateKey = input.readField(MAX_PRIVATE_KEY_BYTES)
                val certificateCount = input.readInt()
                if (certificateCount <= 0 || certificateCount > MAX_CERTIFICATE_CHAIN_LENGTH) {
                    throw KeyStoreException("Invalid PKCS12 certificate chain")
                }
                val certificateChain: Array<Certificate> = Array(certificateCount) {
                    val encoded = input.readField(MAX_CERTIFICATE_BYTES)
                    val publicKey = input.readField(MAX_PRIVATE_KEY_BYTES)
                    KeyStoreCertificate(encoded, EncodedPublicKey("RSA", publicKey))
                }
                parsedEntries[normalizeAlias(alias)] = KeyEntry(
                    alias,
                    EncodedPrivateKey("RSA", privateKey),
                    password?.copyOf(),
                    certificateChain,
                )
            }
            if (input.available() != 0) throw KeyStoreException("Trailing PKCS12 KeyStore data")
        } catch (error: KeyStoreException) {
            throw error
        } catch (error: Exception) {
            throw KeyStoreException("Invalid PKCS12 KeyStore data", error)
        }

        entries.clear()
        entries.putAll(parsedEntries)
        initialized = true
    }

    public fun store(stream: OutputStream, password: CharArray?) {
        requireInitialized()
        requirePKCS12()
        val storePassword = password?.concatToString() ?: ""
        val wireBytes = ByteArrayOutputStream()
        val wire = DataOutputStream(wireBytes)
        wire.writeInt(KEYSTORE_WIRE_MAGIC)
        wire.writeInt(KEYSTORE_WIRE_VERSION)
        wire.writeInt(entries.size)
        for (entry in entries.values) {
            val entryPassword = entry.password
            if (entryPassword != null && (password == null || !entryPassword.contentEquals(password))) {
                throw KeyStoreException("PKCS12 requires each key password to match the KeyStore password")
            }
            wire.writeField(entry.alias.encodeToByteArray())
            val encodedKey = entry.key.encoded ?: throw KeyStoreException("Private key has no encoding")
            wire.writeField(encodedKey)
            val chain = entry.certificateChain
            if (chain.isEmpty() || chain.size > MAX_CERTIFICATE_CHAIN_LENGTH) {
                throw KeyStoreException("Invalid certificate chain for ${entry.alias}")
            }
            wire.writeInt(chain.size)
            for (certificate in chain) {
                wire.writeField(certificate.encoded)
                val publicKey = certificate.publicKey.encoded
                    ?: throw KeyStoreException("Certificate public key has no encoding")
                wire.writeField(publicKey)
            }
        }
        val wireData = wireBytes.toByteArray()
        if (wireData.size > MAX_KEYSTORE_BYTES) throw KeyStoreException("PKCS12 KeyStore is too large")
        val encodedStore = ByteArray(minOf(MAX_KEYSTORE_BYTES, maxOf(8192, wireData.size * 2 + 8192)))
        val encodedLength = storePKCS12(storePassword, wireData, encodedStore)
        if (encodedLength <= 0 || encodedLength > encodedStore.size) {
            throw KeyStoreException("Could not store PKCS12 KeyStore")
        }
        stream.write(encodedStore, 0, encodedLength)
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

    private fun requirePKCS12() {
        if (!type.equals("PKCS12", ignoreCase = true)) {
            throw KeyStoreException("$type KeyStore not available")
        }
    }

    private fun readBounded(stream: InputStream): ByteArray {
        val result = ByteArrayOutputStream()
        val buffer = ByteArray(8192)
        while (true) {
            val count = stream.read(buffer, 0, buffer.size)
            if (count < 0) break
            if (count == 0) continue
            if (result.size() > MAX_KEYSTORE_BYTES - count) {
                throw KeyStoreException("PKCS12 KeyStore is too large")
            }
            result.write(buffer, 0, count)
        }
        return result.toByteArray()
    }

    private fun normalizeAlias(alias: String): String = alias.lowercase()

    public companion object {
        public fun getDefaultType(): String = "pkcs12"

        public fun getInstance(type: String): KeyStore {
            if (!type.equals("PKCS12", ignoreCase = true)) {
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

private class KeyStoreCertificate(
    override val encoded: ByteArray,
    override val publicKey: PublicKey,
) : Certificate("X.509")

private fun DataInputStream.readField(maximumLength: Int): ByteArray {
    val length = readInt()
    if (length < 0 || length > maximumLength) throw KeyStoreException("Invalid PKCS12 field length")
    val field = ByteArray(length)
    readFully(field)
    return field
}

private fun DataOutputStream.writeField(value: ByteArray) {
    writeInt(value.size)
    write(value)
}

private const val KEYSTORE_WIRE_MAGIC = 0x4b4a4331
private const val KEYSTORE_WIRE_VERSION = 1
private const val MAX_KEYSTORE_BYTES = 16 * 1024 * 1024
private const val MAX_KEYSTORE_ENTRIES = 1024
private const val MAX_ALIAS_BYTES = 4096
private const val MAX_PRIVATE_KEY_BYTES = 1024 * 1024
private const val MAX_CERTIFICATE_BYTES = 4 * 1024 * 1024
private const val MAX_CERTIFICATE_CHAIN_LENGTH = 32

@KsSymbolName("__kk_security_pkcs12_load")
private external fun loadPKCS12(input: ByteArray, password: String, output: ByteArray): Int

@KsSymbolName("__kk_security_pkcs12_store")
private external fun storePKCS12(password: String, input: ByteArray, output: ByteArray): Int
