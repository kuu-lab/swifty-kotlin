// KUU-1974: public imports retain the represented class type and primary-only selection.
import kotlin.reflect.KClass
import kotlin.reflect.KFunction
import kotlin.reflect.full.primaryConstructor
import kotlin.reflect.full.primaryConstructor as primary

class EmptyPrimary
class PrimaryWithSecondary(val value: Int) {
    constructor() : this(0)
}
class SecondaryOnly {
    constructor(value: Int)
}
interface NoConstructor
object Singleton
class DefaultPrimary(val name: String = "default", val age: Int = 7)

fun <T : Any> constructorOf(klass: KClass<T>): KFunction<T>? = klass.primaryConstructor

fun main() {
    val empty: KFunction<EmptyPrimary>? = EmptyPrimary::class.primaryConstructor
    println(empty != null)
    println(empty!!.parameters.size)
    val instance: EmptyPrimary = empty.call()
    println(instance is EmptyPrimary)

    val primary: KFunction<PrimaryWithSecondary>? = PrimaryWithSecondary::class.primary
    println(PrimaryWithSecondary::class.constructors.size)
    println(primary!!.parameters.size)
    val value: PrimaryWithSecondary = primary.call(42)
    println(value.value)

    println(SecondaryOnly::class.constructors.size)
    println(SecondaryOnly::class.primaryConstructor == null)
    println(NoConstructor::class.primary == null)
    println(Singleton::class.primaryConstructor == null)

    val defaults: KFunction<DefaultPrimary> = constructorOf(DefaultPrimary::class)!!
    println(defaults.parameters.map { "${it.name}:${it.isOptional}" })
    val defaultValue: DefaultPrimary = defaults.callBy(emptyMap())
    println("${defaultValue.name}:${defaultValue.age}")
    val partial: DefaultPrimary = defaults.callBy(mapOf(defaults.parameters[0] to "chosen"))
    println("${partial.name}:${partial.age}")
    val direct: DefaultPrimary = defaults.call("direct", 9)
    println("${direct.name}:${direct.age}")
}
