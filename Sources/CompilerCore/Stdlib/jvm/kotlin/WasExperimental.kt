package kotlin

@kotlin.annotation.Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY, AnnotationTarget.CONSTRUCTOR, AnnotationTarget.FUNCTION, AnnotationTarget.TYPEALIAS)
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
internal annotation class WasExperimental(vararg val markerClass: kotlin.reflect.KClass<out Annotation>)
