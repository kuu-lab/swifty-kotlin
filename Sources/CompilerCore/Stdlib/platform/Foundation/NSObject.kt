package platform.Foundation

/** Typed facade over an ARC-owned Foundation object; contains no SDK emulation. */
public open class NSObject internal constructor(internal val __handle: Long) {
    public constructor() : this(__foundation_object_create())
    init { __foundation_attach(this, __handle) }
    override fun equals(other: Any?): Boolean = other is NSObject &&
        __foundation_object_equals(__handle, other.__handle)
    override fun hashCode(): Int = __foundation_object_hash(__handle)
}

internal fun __wrapFoundation(handle: Long): NSObject = when (__foundation_object_kind(handle)) {
    1 -> NSData(handle)
    2 -> NSError(handle)
    3 -> NSInputStream(handle)
    4 -> NSOutputStream(handle)
    5 -> NSRunLoop(handle)
    6 -> NSThread(handle)
    else -> NSObject(handle)
}
