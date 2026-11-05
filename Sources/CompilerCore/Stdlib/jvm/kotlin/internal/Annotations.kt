package kotlin.internal

// Mirrors the remaining declarations of the common
// Stdlib/kotlin/internal/Annotations.kt. All of them are compile-time-only
// markers (inlining policy, overload resolution, inference constraints,
// parameter-name stability, runtime symbol naming); consumer compiles inject
// this file as a residual-stdlib declaration that is never emitted, so the
// JVM backend drops applications instead of attaching a classfile plan.

internal annotation class KsSymbolName(val name: String)

internal annotation class KsNoInline

// The inferred type must occur in argument, receiver, or expected types.
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.TYPE_PARAMETER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class OnlyInputTypes

/**
 * Specifies that this function should not be called directly without inlining.
 */
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class InlineOnly

/** Marks Kotlin declarations that model Java methods whose parameter names are unstable. */
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class NonStableParameterNames
