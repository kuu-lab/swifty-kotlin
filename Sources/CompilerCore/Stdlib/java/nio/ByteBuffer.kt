package java.nio

/**
 * Minimal Kotlin source-backed implementation of [java.nio.ByteBuffer] for
 * the operations required by [kotlin.uuid] extensions. This is not a full
 * NIO implementation; it only models the subset used by the bundled stdlib.
 */
public class ByteBuffer private constructor(
    private val bytes: ByteArray,
) {
    private var _position: Int = 0
    private var _limit: Int = bytes.size

    public companion object {
        public fun allocate(capacity: Int): ByteBuffer {
            return ByteBuffer(ByteArray(capacity))
        }

        public fun wrap(array: ByteArray): ByteBuffer {
            return ByteBuffer(array)
        }
    }

    public fun capacity(): Int = bytes.size

    public fun position(): Int = _position

    public fun position(newPosition: Int): ByteBuffer {
        if (newPosition < 0 || newPosition > _limit) {
            throw IndexOutOfBoundsException("position: $newPosition, limit: $_limit")
        }
        _position = newPosition
        return this
    }

    public fun limit(): Int = _limit

    public fun limit(newLimit: Int): ByteBuffer {
        if (newLimit < 0 || newLimit > capacity()) {
            throw IndexOutOfBoundsException("limit: $newLimit, capacity: ${capacity()}")
        }
        _limit = newLimit
        if (_position > _limit) {
            _position = _limit
        }
        return this
    }

    public fun array(): ByteArray = bytes

    public fun hasArray(): Boolean = true

    public fun remaining(): Int = _limit - _position

    public fun hasRemaining(): Boolean = _position < _limit

    public fun get(): Byte {
        if (_position >= _limit) {
            throw IndexOutOfBoundsException("position: $_position, limit: $_limit")
        }
        return bytes[_position++]
    }

    public fun get(index: Int): Byte {
        if (index < 0 || index >= _limit) {
            throw IndexOutOfBoundsException("index: $index, limit: $_limit")
        }
        return bytes[index]
    }

    public fun put(b: Byte): ByteBuffer {
        if (_position >= _limit) {
            throw IndexOutOfBoundsException("position: $_position, limit: $_limit")
        }
        bytes[_position++] = b
        return this
    }

    public fun put(index: Int, b: Byte): ByteBuffer {
        if (index < 0 || index >= _limit) {
            throw IndexOutOfBoundsException("index: $index, limit: $_limit")
        }
        bytes[index] = b
        return this
    }
}
