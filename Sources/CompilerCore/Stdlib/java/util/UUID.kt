package java.util

/**
 * Source-backed shell for Java's immutable UUID value.
 *
 * Kotlin/Native only needs the Java-compatible two-long constructor here so
 * `kotlin.uuid.toKotlinUuid()` can receive a constructed Java UUID. The
 * remaining JDK factory and accessor API is outside KSP-715.
 */
public class UUID(
    private val mostSignificantBits: Long,
    private val leastSignificantBits: Long,
)
