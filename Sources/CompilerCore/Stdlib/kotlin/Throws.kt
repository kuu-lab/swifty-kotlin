package kotlin

/**
 * Marks the annotated declaration as throwing the specified checked exceptions.
 */
@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.CONSTRUCTOR,
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
public annotation class Throws
