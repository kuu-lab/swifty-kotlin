import kotlin.reflect.KParameter

fun named(value: Int, text: String? = null): Int = value
class Counter { fun add(delta: Int): Int = delta }
fun main() {
    val reference = ::named
    println(reference.name)
    println(reference.parameters[0].name)
    println(reference.parameters[1].name)
    val parameter: KParameter = reference.parameters[1]
    println(parameter.name)
    println(parameter.index)
    println(parameter.isOptional)
    val unbound = Counter::add
    println(unbound.parameters[0].name)
    println(unbound.parameters[1].name)
    println((Counter()::add).parameters[0].name)
}
