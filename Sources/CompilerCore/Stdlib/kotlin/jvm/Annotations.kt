package kotlin.jvm

import kotlin.reflect.KClass

@Target(AnnotationTarget.CLASS)
public annotation class JvmInline

@Target(AnnotationTarget.CLASS)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
@SinceKotlin("1.5")
public annotation class JvmRecord

@Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.FIELD,
    AnnotationTarget.FILE
)
public annotation class JvmName(val name: String)

@Target(AnnotationTarget.FILE)
public annotation class JvmMultifileClass

@Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER
)
public annotation class JvmStatic

@Target(AnnotationTarget.FUNCTION, AnnotationTarget.CONSTRUCTOR)
public annotation class JvmOverloads

// Marker only: synchronization is a JVM bytecode flag; on native this is a
// no-op, matching Kotlin/Native's treatment of the optional expectation.
@Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER
)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
public annotation class Synchronized

@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
public annotation class Volatile

@Target(AnnotationTarget.FIELD)
@Retention(AnnotationRetention.SOURCE)
@MustBeDocumented
public annotation class Transient

@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.TYPE
)
@Retention(AnnotationRetention.BINARY)
@MustBeDocumented
public annotation class JvmSuppressWildcards(val suppress: Boolean = true)

@Target(AnnotationTarget.TYPE)
@Retention(AnnotationRetention.BINARY)
@MustBeDocumented
public annotation class JvmWildcard

@Retention(AnnotationRetention.BINARY)
@MustBeDocumented
@SinceKotlin("2.2")
@ExperimentalStdlibApi
@Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.CLASS
)
public annotation class JvmExposeBoxed(val jvmName: String = "")

// Generic extension properties are not yet supported by the parser. Keep the
// Annotation upper bound, as with the source-backed KClass extension properties.
public val Annotation.annotationClass: KClass<out Annotation>
    get() = this::class
