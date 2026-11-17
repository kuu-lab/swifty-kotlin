@file:kotlin.jvm.JvmName("Reflection")
package kotlin.jvm.internal

import kotlin.reflect.KType
import kotlin.reflect.KTypeProjection
import kotlin.reflect.jvm.internal.RuntimeClassType
fun <T> getOrCreateKotlinClass(type: java.lang.Class<T>): kotlin.reflect.KClass<T> = ClassReference<T>(type) as kotlin.reflect.KClass<T>

fun getOrCreateKotlinClasses(types: Array<java.lang.Class<*>>): Array<kotlin.reflect.KClass<*>> = Array<kotlin.reflect.KClass<*>>(types.size) { getOrCreateKotlinClass(types[it]) }

fun property1(reference: PropertyReference1): kotlin.reflect.KProperty1<Any?, Any?> = reference

fun mutableProperty1(reference: MutablePropertyReference1): kotlin.reflect.KMutableProperty1<Any?, Any?> = reference

fun property2(reference: PropertyReference2): kotlin.reflect.KProperty2<Any?, Any?, Any?> = reference

fun typeOf(type: java.lang.Class<*>): KType = RuntimeClassType(type)

fun typeOf(type: java.lang.Class<*>, argument: KTypeProjection): KType =
    RuntimeClassType(type, false, listOf(argument))

fun typeOf(type: java.lang.Class<*>, first: KTypeProjection, second: KTypeProjection): KType =
    RuntimeClassType(type, false, listOf(first, second))

fun typeOf(type: java.lang.Class<*>, vararg arguments: KTypeProjection): KType =
    RuntimeClassType(type, false, arguments.toList())

fun nullableTypeOf(type: java.lang.Class<*>): KType = RuntimeClassType(type, true)

fun nullableTypeOf(type: java.lang.Class<*>, argument: KTypeProjection): KType =
    RuntimeClassType(type, true, listOf(argument))

fun nullableTypeOf(type: java.lang.Class<*>, first: KTypeProjection, second: KTypeProjection): KType =
    RuntimeClassType(type, true, listOf(first, second))

fun nullableTypeOf(type: java.lang.Class<*>, vararg arguments: KTypeProjection): KType =
    RuntimeClassType(type, true, arguments.toList())
