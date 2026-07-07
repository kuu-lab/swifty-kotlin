package kotlin.uuid

// MIGRATION-UUID-001: Uuid class API migrated to Kotlin source.
// Migration source: Sources/Runtime/RuntimeUuid.swift
//
// The sema migration bridge maps the public source declarations below to
// their kk_uuid_* runtime ABI entries. APIs that are not declared here still
// come from HeaderHelpers+SyntheticUuidStubs.swift.

/**
 * Represents a Universally Unique Identifier (UUID) as defined by RFC 9562.
 *
 * Backed at runtime by a two-Long box (mostSignificantBits / leastSignificantBits).
 * All factory and instance methods delegate to the native kk_uuid_* ABI.
 */
@ExperimentalUuidApi
public class Uuid {

    // Companion factory methods

    public companion object {

        /**
         * Generates a cryptographically random version-4 UUID.
         */
        public fun random(): Uuid = Uuid()  // kk_uuid_random

        /**
         * Parses a UUID from its standard hyphenated string representation
         * (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) or from a 32-character hex
         * string without separators.
         *
         * @throws IllegalArgumentException if [uuidString] is not a valid UUID.
         */
        public fun parse(uuidString: String): Uuid = Uuid()  // kk_uuid_parse
    }

    // Instance methods

    /**
     * Returns the standard hyphenated UUID string representation.
     * Example: `"550e8400-e29b-41d4-a716-446655440000"`
     */
    public override fun toString(): String = ""  // kk_uuid_toString

    /**
     * Returns a [Pair] of (mostSignificantBits, leastSignificantBits) as [Long] values.
     */
    public fun toLongs(): Pair<Long, Long> = Pair(0L, 0L)  // kk_uuid_toLongs

    /**
     * Serialises this UUID to a big-endian 16-byte [ByteArray].
     */
    public fun toByteArray(): ByteArray = ByteArray(16)  // kk_uuid_toByteArray
}
