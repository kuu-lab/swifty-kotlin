package java.util.zip

public interface Checksum {
    public fun update(value: Int)

    public fun update(data: ByteArray, offset: Int, length: Int)

    public fun update(data: ByteArray) = update(data, 0, data.size)

    public fun getValue(): Long

    /**
     * JVM synthetic property for `getValue()` — on the JVM `getValue()` is a
     * Java `get`-getter, so `checksum.value` reads the checksum. The bundled
     * Kotlin surface cannot synthesize Java properties, so the `val` models
     * the dual access explicitly (KUU-3988 / KUU-4047).
     */
    public val value: Long
        get() = getValue()

    public fun reset()
}
