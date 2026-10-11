package kotlinx.cinterop

/**
 * Marker for declarations that depend on numeric types of different bit width on at least two platforms.
 *
 * @param actualPlatformTypes Contains platform types represented as `{konanTarget}: {type fqn}`
 * e.g. ["linux_x64: kotlin.Int", "linux_arm64: kotlin.Long"]
 */
@Suppress("unused") // Is emitted by the Commonizer
@Target(AnnotationTarget.TYPEALIAS, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
@Retention(AnnotationRetention.BINARY)
@RequiresOptIn(
        message = "The declaration is using numbers with different bit widths in least two actual platforms. " +
                "Such types shall not be used in user-defined 'expect fun' signatures",
        level = RequiresOptIn.Level.ERROR
)
public annotation class UnsafeNumber(val actualPlatformTypes: Array<String>)

// Primitive conversions replace the Native typed intrinsic with Kotlin bodies.
@ExperimentalForeignApi
public inline fun <reified R : Any> Byte.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> Short.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> Int.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> Long.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> UByte.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> UShort.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> UInt.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
@ExperimentalForeignApi
public inline fun <reified R : Any> ULong.convert(): R = when (R::class) {
    Byte::class -> toByte() as R
    Short::class -> toShort() as R
    Int::class -> toInt() as R
    Long::class -> toLong() as R
    UByte::class -> toUByte() as R
    UShort::class -> toUShort() as R
    UInt::class -> toUInt() as R
    ULong::class -> toULong() as R
    else -> throw IllegalArgumentException("Unsupported primitive conversion")
}
