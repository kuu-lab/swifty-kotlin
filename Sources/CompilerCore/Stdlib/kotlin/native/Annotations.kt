package kotlin.native

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FIELD,
    AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.RequiresOptIn(
    message = "Freezing API is deprecated since 1.7.20. See https://kotlinlang.org/docs/native-migration-guide.html for details",
    level = RequiresOptIn.Level.WARNING
)
public annotation class FreezingIsDeprecated

@kotlin.annotation.Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.ANNOTATION_CLASS,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.FIELD,
    AnnotationTarget.LOCAL_VARIABLE,
    AnnotationTarget.VALUE_PARAMETER,
    AnnotationTarget.CONSTRUCTOR,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY_GETTER,
    AnnotationTarget.PROPERTY_SETTER,
    AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.RequiresOptIn(
    message = "This API is obsolete and subject to removal in a future release.",
    level = RequiresOptIn.Level.ERROR
)
public annotation class ObsoleteNativeApi

@kotlin.annotation.Target(AnnotationTarget.PROPERTY)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.ExperimentalStdlibApi
@kotlin.Deprecated(
    message = "This annotation is a temporal migration assistance and may be removed in the future releases, please consider filing an issue about the case where it is needed"
)
public annotation class EagerInitialization

@kotlin.annotation.Target(
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY
)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.experimental.ExperimentalNativeApi
public annotation class NoInline
