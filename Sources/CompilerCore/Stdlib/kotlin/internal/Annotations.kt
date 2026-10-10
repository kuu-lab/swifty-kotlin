package kotlin.internal

internal annotation class KsSymbolName(val name: String)

internal annotation class KsNoInline

// The inferred type must occur in argument, receiver, or expected types.
@Target(AnnotationTarget.TYPE_PARAMETER)
@Retention(AnnotationRetention.BINARY)
internal annotation class OnlyInputTypes
