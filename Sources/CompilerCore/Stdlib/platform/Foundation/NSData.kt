@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package platform.Foundation
import kotlinx.cinterop.*
public class NSData internal constructor(handle: Long) : NSObject(handle) {
    public constructor() : this(__foundation_data_create(null, 0uL, false, false))
    public val length: ULong get() = __foundation_data_length(__handle)
    public val bytes: CPointer<ByteVar>? get() = __foundation_data_bytes(__handle)
    public companion object {}
}
public fun NSData.Companion.data(): NSData = NSData()
public fun NSData.Companion.create(bytes: CPointer<*>?, length: ULong): NSData =
    NSData(__foundation_data_create(bytes, length, false, false))
public fun NSData.Companion.create(bytesNoCopy: CPointer<*>?, length: ULong,
    freeWhenDone: Boolean = true): NSData =
    NSData(__foundation_data_create(bytesNoCopy, length, true, freeWhenDone))
public fun NSData.Companion.create(base64EncodedString: String, options: ULong): NSData? =
    __foundation_data_base64(base64EncodedString, options)?.let { NSData(it) }
