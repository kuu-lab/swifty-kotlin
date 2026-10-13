package java.nio

/** Source-backed base needed by original Java-8-compatible ByteBuffer casts. */
public abstract class Buffer protected constructor() {
    public abstract fun capacity(): Int
    public abstract fun position(): Int
    public abstract fun position(newPosition: Int): Buffer
    public abstract fun limit(): Int
    public abstract fun limit(newLimit: Int): Buffer
    public abstract fun mark(): Buffer
    public abstract fun reset(): Buffer
    public abstract fun clear(): Buffer
    public abstract fun flip(): Buffer
    public abstract fun rewind(): Buffer
    public abstract fun remaining(): Int
    public abstract fun hasRemaining(): Boolean
    public abstract fun isReadOnly(): Boolean
    public abstract fun isDirect(): Boolean
    public abstract fun hasArray(): Boolean
    public abstract fun array(): Any
    public abstract fun arrayOffset(): Int
}
