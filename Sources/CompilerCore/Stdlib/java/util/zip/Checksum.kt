package java.util.zip

public interface Checksum {
    public fun update(value: Int)

    public fun update(data: ByteArray, offset: Int, length: Int)

    public fun update(data: ByteArray) = update(data, 0, data.size)

    public fun getValue(): Long

    public fun reset()
}
