import kotlin.reflect.*

open class VisibilityBox<T>(val v: T) {
    fun publicFn(): Int = 1
    private fun privateFn(): String = "p"
    internal fun internalFn(): T? = null
    protected fun protectedFn(): Boolean = true
    val publicProp: List<Int> = emptyList()
    private val privateProp: T? = null
}

class VisibilityChild : VisibilityBox<Int>(0) {
    fun childFn(): Unit = Unit
}

fun main() {
    val k = VisibilityBox::class
    val byName = k.members.associateBy { it.name }
    for (n in listOf("publicFn", "privateFn", "internalFn", "protectedFn", "publicProp", "privateProp")) {
        println("$n vis=" + byName[n]?.visibility)
    }
    val publicFn = byName["publicFn"] as KFunction<*>
    println("publicFn rt=" + publicFn.returnType + " cls=" + publicFn.returnType.classifier + " null=" + publicFn.returnType.isMarkedNullable)
    val internalFn = byName["internalFn"] as KFunction<*>
    println("internalFn rt=" + internalFn.returnType + " null=" + internalFn.returnType.isMarkedNullable)
    val publicProp = byName["publicProp"] as KProperty<*>
    println("publicProp rt=" + publicProp.returnType + " args=" + publicProp.returnType.arguments)
    val ctor = k.constructors.first()
    println("ctor rt=" + ctor.returnType + " cls=" + ctor.returnType.classifier + " vis=" + ctor.visibility)
    val child = VisibilityChild::class
    println("inherited vis=" + child.members.first { it.name == "internalFn" }?.visibility)
}
