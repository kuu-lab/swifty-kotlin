import kotlin.reflect.*
interface ReflectedInterface {
    companion object Named {
        init { println("interface-init") }
        const val X = 42
        val ordinary = 43
    }
}
interface DirectInterface {
    companion object {
        init { println("direct-init") }
        const val X = 44
        val ordinary = 45
    }
}
object ReflectedObject {
    init { println("object-init") }
    const val X = 46
}
class ReflectedClass {
    companion object Named {
        init { println("class-init") }
        const val X = 47
    }
}
fun constant(owner: KClass<*>): KCallable<*> {
    for (property in owner.members) if (property.name == "X") return property
    throw IllegalArgumentException("Missing test constant")
}
fun main() {
    println("before")
    val interfaceProperty = constant(ReflectedInterface.Named::class)
    println("interface-discovered")
    println(interfaceProperty.call())
    println(ReflectedInterface.ordinary)
    println(interfaceProperty.call())
    println(DirectInterface.X)
    println(DirectInterface.ordinary)
    val objectProperty = constant(ReflectedObject::class)
    println("object-discovered")
    println(objectProperty.call())
    val classProperty = constant(ReflectedClass.Named::class)
    println("class-discovered")
    println(classProperty.call(ReflectedClass.Named))
    println("after")
}
