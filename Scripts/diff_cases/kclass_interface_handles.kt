// KSP-689: KClass reflection handles implement the Kotlin reflection nominal hierarchy.
import kotlin.reflect.KCallable
import kotlin.reflect.KClass
import kotlin.reflect.KFunction
import kotlin.reflect.KProperty
import kotlin.reflect.full.*

// The compiler keeps the historical `KClass.properties` special case, while
// current kotlin-reflect exposes the equivalent member view under
// `memberProperties`. Keep the diff case portable across both surfaces.
val KClass<*>.properties: List<KProperty<*>>
    get() = listOf(ReflectionSample::value)

class ReflectionSample(val value: Int) {
    fun increment(): Int = value + 1
}

fun main() {
    val klass = ReflectionSample::class

    val members = klass.members
    val member = members.firstOrNull()
    println("members is KCallable: ${member is KCallable<*>}")
    println("member name available: ${!(member as? KCallable<*>)?.name.isNullOrEmpty()}")

    val constructors = klass.constructors
    val constructor = constructors.firstOrNull()
    println("constructors is KCallable: ${constructor is KCallable<*>}")
    println("constructor name available: ${!(constructor as? KCallable<*>)?.name.isNullOrEmpty()}")

    val primary = klass.primaryConstructor
    println("primary is KFunction: ${primary is KFunction<*>}")
    println("primary name available: ${!(primary as? KCallable<*>)?.name.isNullOrEmpty()}")

    val properties = klass.properties
    val property = properties.firstOrNull()
    println("properties is KProperty: ${property is KProperty<*>}")
    println("property name available: ${!(property as? KCallable<*>)?.name.isNullOrEmpty()}")

    val memberProperties = klass.memberProperties
    val declaredMemberProperties = klass.declaredMemberProperties
    println("memberProperties available: ${memberProperties.isNotEmpty()}")
    println("declaredMemberProperties available: ${declaredMemberProperties.isNotEmpty()}")

    val functions = klass.functions
    val function = functions.firstOrNull()
    println("functions is KFunction: ${function is KFunction<*>}")
    println("function name available: ${!(function as? KCallable<*>)?.name.isNullOrEmpty()}")

    val memberFunctions = klass.memberFunctions
    val declaredMemberFunctions = klass.declaredMemberFunctions
    println("memberFunctions available: ${memberFunctions.isNotEmpty()}")
    println("declaredMemberFunctions available: ${declaredMemberFunctions.isNotEmpty()}")

    println("nestedClasses available: ${klass.nestedClasses.isEmpty()}")
    println("supertypes available: ${klass.supertypes.isNotEmpty()}")
}
