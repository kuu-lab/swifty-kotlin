// KUU-3831: FunctionN::class names report the flat `kotlin.FunctionN`
// spelling like Kotlin/JVM, not the internal `kotlin.Function.FunctionN`
// nesting used for synthetic FunctionN identity.
import kotlin.reflect.KClass
import kotlin.reflect.typeOf

class Adder : Function2<Int, Int, Int> {
    override fun invoke(a: Int, b: Int): Int = a + b
}

@OptIn(ExperimentalStdlibApi::class)
fun main() {
    // Base function interface stays `kotlin.Function`.
    println(Function::class.qualifiedName)
    println(Function::class.simpleName)
    println(Function::class.toString())
    // Spot-check arities across the whole Function0..Function22 range.
    println(Function0::class.qualifiedName)
    println(Function1::class.qualifiedName)
    println(Function2::class.qualifiedName)
    println(Function5::class.qualifiedName)
    println(Function10::class.qualifiedName)
    println(Function21::class.qualifiedName)
    println(Function22::class.qualifiedName)
    println(Function0::class.simpleName)
    println(Function5::class.simpleName)
    println(Function22::class.simpleName)
    println(Function5::class.toString())
    // The classifier reached through KType keeps the same KClass.
    println((typeOf<Function2<Int, Int, Int>>().classifier as KClass<*>).qualifiedName)
    println((typeOf<Function2<Int, Int, Int>>().classifier as KClass<*>).simpleName)
    println(Adder::class.supertypes)
    println(Adder::class.supertypes.first().classifier == Function2::class)
    // Non-function stdlib classifiers are unaffected controls.
    println(String::class.qualifiedName)
    println(Map.Entry::class.qualifiedName)
    println(IntRange::class.qualifiedName)
}
