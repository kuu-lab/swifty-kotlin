package golden.sema

import kotlin.reflect.AssociatedObjectKey
import kotlin.reflect.ExperimentalAssociatedObjects
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

fun readCallable(callable: KCallable<*>): String = callable.name

fun readFunction(function: KFunction<*>): KType = function.returnType

fun readProperty(property: KProperty<*>): String = property.name

fun readMutableProperty(property: KMutableProperty<*>): String = property.name

fun acceptAnnotatedElement(element: KAnnotatedElement): KAnnotatedElement = element

fun acceptClassifier(classifier: KClassifier): KClassifier = classifier

fun acceptContainer(container: KDeclarationContainer): KDeclarationContainer = container

fun acceptClass(klass: KClass<*>): KClass<*> = klass

fun acceptTypeParameter(parameter: KTypeParameter): KTypeParameter = parameter

fun acceptType(type: KType): KClassifier? = type.classifier

fun acceptProjection(projection: KTypeProjection): KType? = projection.type

fun acceptVariance(variance: KVariance): KVariance = variance

@OptIn(ExperimentalAssociatedObjects::class)
@AssociatedObjectKey
annotation class AssociatedKey

fun main() {
    val property: KProperty<*> = Sample::value
    val mutableProperty: KMutableProperty<*> = Sample::label
    val function: KFunction<*> = ::readCallable
    val type = typeOf<Map<String, KMutableProperty<*>>>()
    val qualifiedType: KType = kotlin.reflect.typeOf<List<KTypeParameter>>()
    val classIsAnnotated: Boolean = Sample::class is KAnnotatedElement
    val classIsContainer: Boolean = Sample::class is KDeclarationContainer
    val classIsNotMutableProperty: Boolean = Sample::class is KMutableProperty<*>
    val propertyIsCallable: Boolean = mutableProperty is KCallable<*>
    println(readCallable(property))
    println(readFunction(function))
    println(readMutableProperty(mutableProperty))
    println(acceptAnnotatedElement(property))
    println(acceptClassifier(Sample::class))
    println(acceptContainer(Sample::class))
    println(acceptClass(Sample::class))
    println(acceptType(type))
    println(acceptProjection(KTypeProjection(KVariance.OUT, type)))
    println(acceptVariance(KVariance.IN))
    println(type.arguments.size)
}
