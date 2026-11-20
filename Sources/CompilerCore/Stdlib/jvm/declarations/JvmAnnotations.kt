package kotlin.jvm
annotation class JvmInline
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER, kotlin.annotation.AnnotationTarget.FILE)
annotation class JvmName(val name: String)
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FILE)
annotation class JvmMultifileClass
annotation class JvmRepeatable(val value: kotlin.reflect.KClass<out Annotation>)
annotation class JvmField
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FILE, kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER, kotlin.annotation.AnnotationTarget.FIELD)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.SOURCE)
annotation class JvmSynthetic
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.CONSTRUCTOR)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
@kotlin.annotation.MustBeDocumented
annotation class JvmOverloads
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.RUNTIME)
@kotlin.annotation.MustBeDocumented
annotation class JvmStatic
@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.PROPERTY,
    AnnotationTarget.TYPE
)
@Retention(AnnotationRetention.BINARY)
@MustBeDocumented
public annotation class JvmSuppressWildcards(val suppress: Boolean = true)

@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.SOURCE)
@kotlin.annotation.MustBeDocumented
annotation class Synchronized
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FIELD)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.SOURCE)
@kotlin.annotation.MustBeDocumented
annotation class Volatile
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FIELD)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.SOURCE)
@kotlin.annotation.MustBeDocumented
annotation class Transient
