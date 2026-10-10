/* Derived from kotlinx-io 0.9.1 under the Apache-2.0 license. */
package kotlinx.io.bytestring.unsafe

@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@RequiresOptIn(
    level = RequiresOptIn.Level.ERROR,
    message = "This is a unsafe API and its use may corrupt the data stored in a byte string. Make sure you fully read and understand documentation of the declaration that is marked as an unsafe API."
)
public annotation class UnsafeByteStringApi
