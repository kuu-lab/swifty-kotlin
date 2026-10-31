// KUU-3895: `Nothing` inside typeOf must render the Kotlin type name
// `kotlin.Nothing`, never the `java.lang.Void` classifier name — while the
// classifier itself stays `Void::class` like on the JVM. `Nothing?` reaches
// the same token-0 KClass slot through a different name hint, so both
// spellings are exercised.
import kotlin.reflect.KClass
import kotlin.reflect.typeOf
import kotlin.reflect.full.starProjectedType

fun main() {
    println(typeOf<Nothing?>())
    println(typeOf<List<Nothing>>())
    println(typeOf<List<Nothing?>>())
    println(typeOf<Map<String, Nothing>>())
    val classifier = typeOf<List<Nothing>>().arguments[0].type!!.classifier as KClass<*>
    println(classifier)
    println(classifier.qualifiedName)
    println(classifier.simpleName)
    println(classifier == Nothing::class)
    println(Nothing::class)
    println(Nothing::class.qualifiedName)
    println(Nothing::class.simpleName)
    println(Nothing::class.starProjectedType)
    println(typeOf<List<java.lang.Void?>>())
}
