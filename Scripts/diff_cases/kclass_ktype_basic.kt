
import kotlin.reflect.typeOf

fun main() {
    // Test KClass functionality
    val stringClass = String::class
    val intClass = Int::class
    val listClass = List::class

    // Test KClass methods
    println("String simpleName: ${stringClass.simpleName}")
    println("Int simpleName: ${intClass.simpleName}")
    println("List simpleName: ${listClass.simpleName}")

    // Test isInstance
    println("stringClass.isInstance(\"hello\"): ${stringClass.isInstance("hello")}")
    println("intClass.isInstance(42): ${intClass.isInstance(42)}")

    // Test typeOf (do not print KType directly because toString differs)
    val stringType = typeOf<String>()
    val intType = typeOf<Int>()
    println("typeOf<String> succeeded: ${stringType.toString().isNotEmpty()}")
    println("typeOf<Int> succeeded: ${intType.toString().isNotEmpty()}")
}
