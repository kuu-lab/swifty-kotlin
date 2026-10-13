import kotlin.reflect.KClass
import kotlin.reflect.KClassifier
import kotlin.reflect.typeOf

open class ClassifierBase
class ClassifierChild : ClassifierBase()

inline fun <reified T> checkedCast(value: Any): T = value as T

fun checkClassifier(classifier: KClassifier?) {
    val erased: Any = classifier!!
    println(classifier is KClass<*>)
    println(erased is KClass<*>)
    println((classifier as KClass<*>).qualifiedName)
    println((classifier as KClass<Any>).qualifiedName)
    println((erased as? KClass<Any>)?.qualifiedName)
    println(checkedCast<KClass<Any>>(erased).qualifiedName)
}

fun main() {
    checkClassifier(Number::class.supertypes[1].classifier)
    checkClassifier(Number::class.supertypes[0].classifier)
    checkClassifier(typeOf<String>().classifier)
    checkClassifier(ClassifierChild::class.supertypes[0].classifier)
    checkClassifier(String::class)

    val absent: Any? = null
    println(absent is KClass<*>)
    println(absent as? KClass<Any>)
    println(absent as KClass<Any>?)
    val wrong: Any = "wrong"
    println(wrong is KClass<*>)
    println(wrong as? KClass<Any>)
    try {
        wrong as KClass<Any>
        println("unexpected")
    } catch (e: ClassCastException) {
        println("ClassCastException")
    }
    val type: Any = typeOf<String>()
    println(type is KClass<*>)
    try {
        type as KClass<*>
        println("unexpected")
    } catch (e: ClassCastException) {
        println("ClassCastException")
    }
}
