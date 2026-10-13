import kotlin.reflect.KClass
import kotlin.reflect.cast
import kotlin.reflect.safeCast

fun inspect(k: KClass<*>) {
    println(k.isInstance(42))
    println(k.isInstance("other"))
    println(k.isInstance(null))
    println(k.simpleName)
    println(k.cast(42))
    println(k.safeCast(42))
    println(k.safeCast("other"))
    println(k.safeCast(null))
}

fun main() {
    val k: KClass<*> = Int::class
    println(k.isInstance(42))
    inspect(k)
    val typed: KClass<Int> = Int::class
    println(typed.isInstance(42))
    println(typed.isInstance("other"))
    val cast: Int = typed.cast(42)
    val safe: Int? = typed.safeCast(42)
    println(cast)
    println(safe)
    val out: KClass<out Number> = Int::class
    println(out.isInstance(42))
    println(out.isInstance("other"))
    val contravariant: KClass<in Int> = Int::class
    println(contravariant.isInstance(42))
    println(contravariant.isInstance("other"))
    val wide: Any = contravariant.cast(42)
    println(wide)
    val nullable: KClass<*>? = k
    println(nullable?.isInstance(42))
    val absent: KClass<*>? = null
    println(absent?.isInstance(42))
    try {
        k.cast("other")
    } catch (e: ClassCastException) {
        println("cast rejected")
    }
}
