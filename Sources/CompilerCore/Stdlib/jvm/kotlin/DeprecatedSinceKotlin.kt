package kotlin

@kotlin.annotation.Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY, AnnotationTarget.ANNOTATION_CLASS, AnnotationTarget.CONSTRUCTOR, AnnotationTarget.PROPERTY_SETTER, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.TYPEALIAS)
@kotlin.annotation.MustBeDocumented
@SinceKotlin("1.4")
public annotation class DeprecatedSinceKotlin(
    val warningSince: String = "",
    val errorSince: String = "",
    val hiddenSince: String = ""
)
