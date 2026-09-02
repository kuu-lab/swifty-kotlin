package golden.sema

@Target(
    AnnotationTarget.CLASS,
    AnnotationTarget.FUNCTION,
    AnnotationTarget.TYPEALIAS,
)
@Retention(AnnotationRetention.BINARY)
@MustBeDocumented
@Repeatable
annotation class SourceBackedAnnotation

@Retention()
annotation class DefaultRuntimeRetention

@SourceBackedAnnotation
class AnnotatedClass

@SourceBackedAnnotation
fun annotatedFunction() {}

@SourceBackedAnnotation
typealias AnnotatedAlias = String

fun annotationRetentionSurface(): AnnotationRetention = AnnotationRetention.RUNTIME

fun annotationTargetSurface(): AnnotationTarget = AnnotationTarget.TYPEALIAS
