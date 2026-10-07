package kotlin.jvm

import kotlin.reflect.KClass

// Generic extension properties are not yet supported by the parser. Keep the
// Annotation upper bound, as with the source-backed KClass extension properties.
/** Returns the class of this annotation instance. */
public val Annotation.annotationClass: KClass<out Annotation>
    get() = this::class
