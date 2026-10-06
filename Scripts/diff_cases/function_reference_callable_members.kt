// KUU-1309: inferred and interface-typed references expose the KCallable contract.
import kotlin.reflect.KCallable
import kotlin.annotation.Retention as Keep
import kotlin.annotation.AnnotationRetention.SOURCE as SourceRetention

fun add(a: Int, b: Int) = a + b
private fun hidden() = 1
suspend fun suspended() = 2
annotation class Marker
@Keep(value = SourceRetention) annotation class SourceMarker
@kotlin.annotation.Retention(AnnotationRetention.BINARY) annotation class BinaryMarker
@Keep(AnnotationRetention.RUNTIME) annotation class RuntimeMarker
@Marker @SourceMarker @BinaryMarker @RuntimeMarker fun marked() = 1

fun main() {
    val r = ::add
    println(r.parameters.size)
    println(r.callBy(mapOf(r.parameters[0] to 1, r.parameters[1] to 2)))
    println(r.returnType)
    println(r.isSuspend)
    println(r.annotations)
    println(r.visibility)
    val callable: KCallable<Int> = r
    println(callable.parameters.size)
    println(callable.callBy(mapOf(callable.parameters[1] to 4, callable.parameters[0] to 3)))
    println(callable.returnType)
    println(callable.isSuspend)
    println(callable.annotations)
    println(callable.visibility)
    println(::hidden.visibility)
    println(::suspended.isSuspend)
    val markedRef = ::marked
    println(markedRef.annotations.size)
    println(markedRef.annotations.size)
    val annotated: KCallable<Int> = markedRef
    println(annotated.annotations.size)
    println(::marked.annotations.size)
}
