package kotlin.annotation
enum class AnnotationRetention { SOURCE, BINARY, RUNTIME }
enum class AnnotationTarget { CLASS, ANNOTATION_CLASS, TYPE_PARAMETER, PROPERTY, FIELD, LOCAL_VARIABLE, VALUE_PARAMETER, CONSTRUCTOR, FUNCTION, PROPERTY_GETTER, PROPERTY_SETTER, TYPE, EXPRESSION, FILE, TYPEALIAS }
annotation class Retention(val value: AnnotationRetention)
annotation class Target(vararg val allowedTargets: AnnotationTarget)
annotation class MustBeDocumented
annotation class Repeatable