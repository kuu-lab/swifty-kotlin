package kotlin.internal

internal annotation class KsSymbolName(val name: String)

internal annotation class KsNoInline

// The inferred type must occur in argument, receiver, or expected types.
@Target(AnnotationTarget.TYPE_PARAMETER)
@Retention(AnnotationRetention.BINARY)
internal annotation class OnlyInputTypes

@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY, AnnotationTarget.CONSTRUCTOR)
@Retention(AnnotationRetention.BINARY)
internal annotation class LowPriorityInOverloadResolution

/**
 * Specifies that this function should not be called directly without inlining.
 */
@Target(AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.PROPERTY_SETTER)
@Retention(AnnotationRetention.BINARY)
internal annotation class InlineOnly

/** Marks Kotlin declarations that model Java methods whose parameter names are unstable. */
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
internal annotation class NonStableParameterNames
