package kotlin.internal

internal annotation class KsSymbolName(val name: String)

internal annotation class KsNoInline

@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.TYPE_PARAMETER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class OnlyInputTypes

@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class InlineOnly

@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
internal annotation class NonStableParameterNames
