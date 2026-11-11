package kotlin

annotation class OverloadResolutionByLambdaReturnType

@kotlin.annotation.Target(
    kotlin.annotation.AnnotationTarget.CLASS,
    kotlin.annotation.AnnotationTarget.PROPERTY,
    kotlin.annotation.AnnotationTarget.LOCAL_VARIABLE,
    kotlin.annotation.AnnotationTarget.VALUE_PARAMETER,
    kotlin.annotation.AnnotationTarget.CONSTRUCTOR,
    kotlin.annotation.AnnotationTarget.FUNCTION,
    kotlin.annotation.AnnotationTarget.PROPERTY_GETTER,
    kotlin.annotation.AnnotationTarget.PROPERTY_SETTER,
    kotlin.annotation.AnnotationTarget.EXPRESSION,
    kotlin.annotation.AnnotationTarget.FILE,
    kotlin.annotation.AnnotationTarget.TYPEALIAS
)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.SOURCE)
annotation class OptIn(vararg val markerClass: kotlin.reflect.KClass<out Annotation>)
