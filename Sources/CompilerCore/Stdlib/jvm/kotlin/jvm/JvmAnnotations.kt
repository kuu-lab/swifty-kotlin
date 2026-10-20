package kotlin.jvm
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.RUNTIME)
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.CLASS)
annotation class JvmInline
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER, kotlin.annotation.AnnotationTarget.FILE)
annotation class JvmName(val name: String)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
annotation class JvmRepeatable(val value: kotlin.reflect.KClass<out Annotation>)
@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.BINARY)
annotation class JvmField
