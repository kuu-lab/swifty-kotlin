@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class, kotlin.experimental.ExperimentalNativeApi::class)
package platform.Foundation
import kotlinx.cinterop.*
import kotlin.native.ref.WeakReference
import platform.posix.uint8_tVar
public typealias NSStreamStatus = ULong
public typealias NSStreamEvent = ULong
public typealias NSStreamPropertyKey = String
public typealias NSRunLoopMode = String
public const val NSStreamStatusNotOpen: ULong = 0uL
public const val NSStreamStatusOpening: ULong = 1uL
public const val NSStreamStatusOpen: ULong = 2uL
public const val NSStreamStatusReading: ULong = 3uL
public const val NSStreamStatusWriting: ULong = 4uL
public const val NSStreamStatusAtEnd: ULong = 5uL
public const val NSStreamStatusClosed: ULong = 6uL
public const val NSStreamStatusError: ULong = 7uL
public const val NSStreamEventNone: ULong = 0uL
public const val NSStreamEventOpenCompleted: ULong = 1uL
public const val NSStreamEventHasBytesAvailable: ULong = 2uL
public const val NSStreamEventHasSpaceAvailable: ULong = 4uL
public const val NSStreamEventErrorOccurred: ULong = 8uL
public const val NSStreamEventEndEncountered: ULong = 16uL
public const val NSStreamDataWrittenToMemoryStreamKey: String = "NSStreamDataWrittenToMemoryStreamKey"
public const val NSDefaultRunLoopMode: String = "kCFRunLoopDefaultMode"
public interface NSStreamDelegateProtocol {
    public fun stream(aStream: NSStream, handleEvent: NSStreamEvent)
}
public open class NSStream internal constructor(handle: Long) : NSObject(handle) {
    private var weakDelegate: WeakReference<NSStreamDelegateProtocol>? = null
    public open fun open() { __foundation_stream_call(__handle, 0, null, null) }
    public open fun close() { __foundation_stream_call(__handle, 1, null, null) }
    public open fun streamStatus(): ULong = (__foundation_stream_call(__handle, 2, null, null) as Long).toULong()
    public val streamStatus: ULong get() = streamStatus()
    public open fun streamError(): NSError? = (__foundation_stream_call(__handle, 3, null, null) as? Long)?.let { NSError(it) }
    public val streamError: NSError? get() = streamError()
    public open fun delegate(): NSStreamDelegateProtocol? = weakDelegate?.value
    public var delegate: NSStreamDelegateProtocol? get() = delegate()
        set(value) { setDelegate(value) }
    public open fun setDelegate(delegate: NSStreamDelegateProtocol?) {
        weakDelegate = delegate?.let { WeakReference(it) }
        val dispatch: ((ULong) -> Unit)? = if (delegate == null) null else {
            { event: ULong -> weakDelegate?.value?.stream(this, event) }
        }
        __foundation_stream_delegate(__handle, dispatch as Any?)
    }
    public open fun propertyForKey(key: NSStreamPropertyKey): Any? =
        (__foundation_stream_call(__handle, 8, key, null) as? Long)?.let { __wrapFoundation(it) }
    public open fun setProperty(property: Any?, forKey: NSStreamPropertyKey): Boolean =
        __foundation_stream_call(__handle, 11, property, forKey) as Boolean
    public open fun scheduleInRunLoop(aRunLoop: NSRunLoop, forMode: NSRunLoopMode) {
        __foundation_stream_call(__handle, 9, aRunLoop.__handle, forMode)
    }
    public open fun removeFromRunLoop(aRunLoop: NSRunLoop, forMode: NSRunLoopMode) {
        __foundation_stream_call(__handle, 10, aRunLoop.__handle, forMode)
    }
    internal fun __deliverEvent(event: ULong) { __foundation_stream_event(__handle, event) }
    internal fun __installOverrides(input: Boolean) {
        val dispatch: (Int, Any?, Any?) -> Any? = { op, a, b ->
            when (op) {
                0 -> open()
                1 -> close()
                2 -> streamStatus().toLong()
                3 -> streamError()
                4 -> (this as NSInputStream).read(a as CPointer<uint8_tVar>?, (b as Long).toULong())
                5 -> (this as NSOutputStream).write(a as CPointer<uint8_tVar>?, (b as Long).toULong())
                6 -> (this as NSInputStream).hasBytesAvailable()
                7 -> (this as NSOutputStream).hasSpaceAvailable()
                8 -> propertyForKey(a as String)
                9 -> scheduleInRunLoop(NSRunLoop(a as Long), b as String)
                10 -> removeFromRunLoop(NSRunLoop(a as Long), b as String)
                11 -> setProperty(a, b as String)
                12 -> false
                else -> throw IllegalArgumentException("Unknown Foundation stream operation: $op")
            }
        }
        __foundation_stream_install(__handle, dispatch as Any, input)
    }
    public open fun description(): String = toString()
}
public open class NSInputStream internal constructor(handle: Long) : NSStream(handle) {
    public constructor(data: NSData) : this(__foundation_input_create(data.__handle))
    public constructor(uRL: NSURL) : this(__foundation_input_url(uRL.__handle))
    internal constructor() : this(NSData())
    public open fun read(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long =
        __foundation_stream_call(__handle, 4, buffer, maxLength.toLong()) as Long
    public open fun hasBytesAvailable(): Boolean = __foundation_stream_call(__handle, 6, null, null) as Boolean
    public open fun getBuffer(buffer: CPointer<CPointerVar<uint8_tVar>>?, length: CPointer<ULongVar>?): Boolean =
        __foundation_stream_call(__handle, 12, buffer, length) as Boolean
}
public open class NSOutputStream internal constructor(handle: Long) : NSStream(handle) {
    public constructor(toMemory: Unit) : this(__foundation_output_create())
    public open fun write(buffer: CPointer<uint8_tVar>?, maxLength: ULong): Long =
        __foundation_stream_call(__handle, 5, buffer, maxLength.toLong()) as Long
    public open fun hasSpaceAvailable(): Boolean = __foundation_stream_call(__handle, 7, null, null) as Boolean
    public companion object { public fun outputStreamToMemory(): NSOutputStream = NSOutputStream(Unit) }
}
