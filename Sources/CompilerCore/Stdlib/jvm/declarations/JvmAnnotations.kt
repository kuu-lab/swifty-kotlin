package kotlin.jvm
annotation class JvmInline
@kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FUNCTION, kotlin.annotation.AnnotationTarget.PROPERTY_GETTER, kotlin.annotation.AnnotationTarget.PROPERTY_SETTER, kotlin.annotation.AnnotationTarget.FILE)
annotation class JvmName(val name: String)
annotation class JvmRepeatable(val value: kotlin.reflect.KClass<out Annotation>)
annotation class JvmField
