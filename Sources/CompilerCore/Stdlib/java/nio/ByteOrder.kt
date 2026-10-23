package java.nio

/** Byte order used by typed ByteBuffer accessors. */
public enum class ByteOrder {
    BIG_ENDIAN,
    LITTLE_ENDIAN;

    public companion object {
        public fun nativeOrder(): ByteOrder = LITTLE_ENDIAN
    }
}
