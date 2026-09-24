// KSP-1323: kotlin.reflect top-level surface — source-backed interfaces and
// typeOf. (AssociatedObjectKey is Kotlin/Native-only and cannot be exercised
// against the JVM reference compiler.)
import kotlin.reflect.KAnnotatedElement
import kotlin.reflect.KCallable
import kotlin.reflect.KClass
import kotlin.reflect.KClassifier
import kotlin.reflect.KDeclarationContainer
import kotlin.reflect.KFunction
import kotlin.reflect.KMutableProperty
import kotlin.reflect.KProperty
import kotlin.reflect.KType
import kotlin.reflect.KTypeParameter
import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance
import kotlin.reflect.typeOf

class Sample(val value: Int, var label: String)

fun answer(): String = "answer"

fun main() {
    val function: KFunction<*> = ::answer
    val property: KProperty<*> = Sample::value
    val mutableProperty: KMutableProperty<*> = Sample::label

    println(function.name)
    println(property.name)
    println(mutableProperty.name)

    println(typeOf<KFunction<*>>().classifier == KFunction::class)
    println(typeOf<KProperty<String>>())
    println(typeOf<KMutableProperty<Int?>>())
    println(typeOf<KCallable<List<KAnnotatedElement>>>())
    println(typeOf<KDeclarationContainer>().classifier == KDeclarationContainer::class)
    println(typeOf<KClassifier>().classifier == KClassifier::class)
    println(typeOf<KTypeParameter>().classifier == KTypeParameter::class)
    println(typeOf<KAnnotatedElement>().classifier == KAnnotatedElement::class)
    println(typeOf<KClass<*>>().classifier == KClass::class)

    val projection = KTypeProjection(KVariance.IN, typeOf<Int>())
    println(projection.variance == KVariance.IN)
    println(projection.type?.isMarkedNullable == false)

    val nested = typeOf<Map<KMutableProperty<*>, KFunction<*>>>()
    println(nested)
    println(nested.arguments.size)
    println(nested.classifier == Map::class)

    println(kotlin.reflect.typeOf<Long>())
    println(Sample::class is KAnnotatedElement)
    println(Sample::class is KDeclarationContainer)
    println(Sample::class is KMutableProperty<*>)
    println(Sample::label is KAnnotatedElement)
    println(mutableProperty is KCallable<*>)
}
