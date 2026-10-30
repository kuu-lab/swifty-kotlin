// KUU-3828: anonymous object literals have no name in Kotlin reflection.
// KClass.simpleName is null on the JVM even though the compiler registers a
// synthetic __ObjectLiteral_ name; java.lang.Class.getSimpleName() is "".
interface Greeter { fun hello(): String }

val topObject = object {}
val typedTopObject = object : Greeter { override fun hello() = "hi" }
object Named

fun main() {
    val localObject = object {}
    val typedLocal = object : Greeter { override fun hello() = "yo" }
    val erased: Any = localObject
    class Local

    println(localObject::class.simpleName)
    println(topObject::class.simpleName)
    println(typedLocal::class.simpleName)
    println(typedTopObject::class.simpleName)
    println(erased::class.simpleName)
    println(localObject::class.qualifiedName)
    println(topObject::class.qualifiedName)
    println(Local::class.simpleName)
    println(Local::class.qualifiedName)
    println(Named::class.simpleName)
    println(Named::class.qualifiedName)
    println("[${localObject.javaClass.simpleName}]")
    println("[${topObject.javaClass.simpleName}]")
    println(Local().javaClass.simpleName)
}
