// KUU-2049: metadata factories retain the enum helpers used by vararg boxing.
import kotlin.reflect.full.findAnnotation

@Target(AnnotationTarget.EXPRESSION)
@Retention(AnnotationRetention.SOURCE)
annotation class Tag

@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.SOURCE)
annotation class SourceSingle
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.SOURCE)
annotation class SourceMultiple
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
annotation class BinarySingle
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.BINARY)
annotation class BinaryMultiple
@Target(AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class RuntimeSingle
@Target(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)
@Retention(AnnotationRetention.RUNTIME)
annotation class RuntimeMultiple

annotation class Retentions(vararg val values: AnnotationRetention)
@Retentions(AnnotationRetention.SOURCE, AnnotationRetention.BINARY, AnnotationRetention.RUNTIME)
class RetentionValues

fun main() {
    check(Tag::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.EXPRESSION)))
    check(Tag::class.findAnnotation<Target>()!!.allowedTargets[0].name == "EXPRESSION")
    check(Tag::class.findAnnotation<Retention>()!!.value == AnnotationRetention.SOURCE)
    check(SourceSingle::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.FUNCTION)))
    check(SourceMultiple::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)))
    check(SourceMultiple::class.findAnnotation<Target>()!!.allowedTargets[0].name == "CLASS")
    check(SourceMultiple::class.findAnnotation<Target>()!!.allowedTargets[1].name == "FUNCTION")
    check(BinarySingle::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.FUNCTION)))
    check(BinaryMultiple::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)))
    check(RuntimeSingle::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.FUNCTION)))
    check(RuntimeMultiple::class.findAnnotation<Target>()!!.allowedTargets.contentEquals(arrayOf(AnnotationTarget.CLASS, AnnotationTarget.FUNCTION)))
    check(SourceSingle::class.findAnnotation<Retention>()!!.value == AnnotationRetention.SOURCE)
    check(SourceMultiple::class.findAnnotation<Retention>()!!.value == AnnotationRetention.SOURCE)
    check(BinarySingle::class.findAnnotation<Retention>()!!.value == AnnotationRetention.BINARY)
    check(BinaryMultiple::class.findAnnotation<Retention>()!!.value == AnnotationRetention.BINARY)
    check(RuntimeSingle::class.findAnnotation<Retention>()!!.value == AnnotationRetention.RUNTIME)
    check(RuntimeMultiple::class.findAnnotation<Retention>()!!.value == AnnotationRetention.RUNTIME)
    check(RetentionValues::class.findAnnotation<Retentions>()!!.values.contentEquals(arrayOf(AnnotationRetention.SOURCE, AnnotationRetention.BINARY, AnnotationRetention.RUNTIME)))
    check(RetentionValues::class.findAnnotation<Retentions>()!!.values[0].name == "SOURCE")
    check(RetentionValues::class.findAnnotation<Retentions>()!!.values[1].name == "BINARY")
    check(RetentionValues::class.findAnnotation<Retentions>()!!.values[2].name == "RUNTIME")
    println("target:single:multiple:source:binary:runtime")
    println("retention:vararg:source:binary:runtime")
}
