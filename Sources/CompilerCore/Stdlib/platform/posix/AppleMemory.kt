@file:OptIn(kotlinx.cinterop.ExperimentalForeignApi::class)
package platform.posix
import kotlinx.cinterop.*
public typealias uint8_tVar = UByteVar
public fun memcpy(destination: CPointer<*>?, source: CPointer<*>?, length: ULong): CPointer<*>? =
    platform.Foundation.__foundation_memcpy(destination, source, length)
public fun memset(destination: CPointer<*>?, value: Int, length: ULong): CPointer<*>? =
    platform.Foundation.__foundation_memset(destination, value, length)
public fun malloc(length: ULong): CPointer<ByteVar>? = platform.Foundation.__foundation_malloc(length)
public fun free(pointer: CPointer<*>?) { platform.Foundation.__foundation_free(pointer) }
public val errno: Int get() = platform.Foundation.__foundation_errno()
public fun strerror(code: Int): CPointer<ByteVar>? = platform.Foundation.__foundation_strerror(code)
public fun memcpy(destination: CValuesRef<ByteVar>, source: CPointer<*>?, length: ULong): CPointer<*>? =
    platform.Foundation.__foundation_memcpy(kotlinx.cinterop.__byteArrayRefPointer(destination), source, length)
public const val F_OK: Int = 0
public fun access(path: String?, mode: Int): Int = platform.Foundation.__foundation_access(path, mode)
