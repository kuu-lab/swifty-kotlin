@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)

package platform.Foundation

import kotlinx.cinterop.CPointer

public class NSMutableData internal constructor(handle: Long) : NSData(handle) {
    public constructor() : this(__foundation_mutable_data_create())

    public fun appendBytes(bytes: CPointer<*>?, length: ULong) {
        __foundation_mutable_data_append(__handle, bytes, length)
    }
}
