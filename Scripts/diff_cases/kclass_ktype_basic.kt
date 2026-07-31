// SKIP-DIFF (DEBT-DIFF-007): KClass.toString() prints a raw pointer/address (e.g. "50138941760")
// instead of the real Kotlin format "class kotlin.String" — no `kk_kclass_toString`-style override
// exists in Runtime; see docs/diff-skip-inventory.md (DEBT-DIFF-007).
import kotlin.reflect.KType
import kotlin.reflect.typeOf

fun main() {
    // Test KClass functionality
    val stringClass = String::class
    val intClass = Int::class
    val listClass = List::class
    
    println("String::class: $stringClass")
    println("Int::class: $intClass")
    println("List::class: $listClass")
    
    // Test KClass methods
    println("String simpleName: ${stringClass.simpleName}")
    println("Int simpleName: ${intClass.simpleName}")
    
    // Test isInstance
    println("stringClass.isInstance(\"hello\"): ${stringClass.isInstance("hello")}")
    println("intClass.isInstance(42): ${intClass.isInstance(42)}")
    
    // Test typeOf
    val stringType = typeOf<String>()
    val intType = typeOf<Int>()
    
    println("typeOf<String>(): $stringType")
    println("typeOf<Int>(): $intType")
    
    // Test KType from a reified type argument
    val stringKType: KType = stringType
    val intKType: KType = intType
    
    println("String KType: $stringKType")
    println("Int KType: $intKType")
}
