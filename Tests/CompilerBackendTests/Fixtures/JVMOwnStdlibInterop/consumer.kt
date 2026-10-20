import kotlin.coroutines.*
import kotlin.sequences.*
import kotlin.reflect.KFunction
import kotlin.reflect.KMutableProperty
import kotlin.reflect.KProperty1

@kotlin.annotation.Retention(kotlin.annotation.AnnotationRetention.RUNTIME)
annotation class Label(val text: String = "default")
val answer = 7
fun main() {
    println(sequence { yield(1); yieldAll(listOf(2, 3)) }.toList())
    println(Regex("[a-z]+").findAll("a B c").map { it.value }.toList())
    var attempts = 0
    val once = lazy { attempts++; "ready" }; println(once.value); println(once.value); println(attempts)
    val work: suspend () -> Unit = {
        val value = suspendCoroutine<Int> { continuation -> continuation.resume(42) }
        println(value)
        println(4294967295u)
    }
    work.startCoroutine(object: Continuation<Unit> {
        override val context: CoroutineContext = EmptyCoroutineContext
        override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
    })
    println(Int::class == (1 as Any)::class)
    println(::answer is KMutableProperty<*>); println(::answer is KProperty1<*, *>); println(::answer is KFunction<*>)
    val f: () -> Int = ::answer; println(f())
    println(Label::class.constructors.first().callBy(emptyMap()).text)
}
