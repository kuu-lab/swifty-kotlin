@file:OptIn(kotlin.ExperimentalStdlibApi::class)

package kotlin.concurrent

import kotlin.native.internal.NativePtr

/**
 * Kotlin source-backed constructor for the legacy native-pointer atomic API.
 *
 * The value property and receiver operations remain owned by KSP-1096.
 */
@SinceKotlin("1.9")
public class AtomicNativePtr {
    public constructor(value: NativePtr)

    // The backing storage is shared with the receiver migration owned by KSP-1096.
    @PublishedApi
    internal val value: NativePtr = value
}
