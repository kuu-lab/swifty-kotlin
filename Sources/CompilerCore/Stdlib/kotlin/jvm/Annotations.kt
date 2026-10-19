package kotlin.jvm

import kotlin.reflect.KClass

@Target(AnnotationTarget.CLASS)
public annotation class JvmInline

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

@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY)
public annotation class JvmStatic

@Target(AnnotationTarget.FUNCTION, AnnotationTarget.CONSTRUCTOR)
public annotation class JvmOverloads

// Generic extension properties are not yet supported by the parser. Keep the
// Annotation upper bound, as with the source-backed KClass extension properties.
public val Annotation.annotationClass: KClass<out Annotation>
    get() = this::class
