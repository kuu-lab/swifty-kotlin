package java.nio

public enum class ByteOrder {
    BIG_ENDIAN,
    LITTLE_ENDIAN;

    public companion object {
        public fun nativeOrder(): ByteOrder = LITTLE_ENDIAN
    }
}
