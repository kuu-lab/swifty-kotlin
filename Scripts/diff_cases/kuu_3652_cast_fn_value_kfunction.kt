// KUU-3652: a stable local smart-cast to KFunction keeps its structural
// function type — the intersection stays invocable.
fun render(value: Boolean): String = value.toString()

class Greeter {
    fun greet(loud: Boolean): String = if (loud) "HI" else "hi"
}

fun main() {
    val reference: (Boolean) -> Any = ::render
    val reflected = reference as kotlin.reflect.KFunction<*>
    println(reference(true))
    println(reference.invoke(false))
    println(reflected.name)

    val greeter = Greeter()
    val member: (Boolean) -> String = greeter::greet
    val memberReflected = member as kotlin.reflect.KFunction<*>
    println(member(true))
    println(memberReflected.name)

    if (reference is kotlin.reflect.KFunction<*>) {
        println(reference(false))
        println(reference.name)
    }
}
