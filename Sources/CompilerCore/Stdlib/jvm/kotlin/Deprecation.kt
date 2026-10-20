package kotlin

@kotlin.annotation.Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION, AnnotationTarget.PROPERTY, AnnotationTarget.ANNOTATION_CLASS, AnnotationTarget.CONSTRUCTOR, AnnotationTarget.PROPERTY_SETTER, AnnotationTarget.PROPERTY_GETTER, AnnotationTarget.TYPEALIAS)
@kotlin.annotation.MustBeDocumented
public annotation class Deprecated(val message: String, val replaceWith: ReplaceWith = ReplaceWith(""), val level: DeprecationLevel = DeprecationLevel.WARNING)

@kotlin.annotation.Target()
@kotlin.annotation.Retention(AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
public annotation class ReplaceWith(val expression: String, vararg val imports: String)

public enum class DeprecationLevel { WARNING, ERROR, HIDDEN }
