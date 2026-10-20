@file:kotlin.jvm.JvmName("Reflection")
package kotlin.jvm.internal
fun <T> getOrCreateKotlinClass(type: java.lang.Class<T>): kotlin.reflect.KClass<T> = ClassReference<T>(type) as kotlin.reflect.KClass<T>

fun getOrCreateKotlinClasses(types: Array<java.lang.Class<*>>): Array<kotlin.reflect.KClass<*>> = Array<kotlin.reflect.KClass<*>>(types.size) { getOrCreateKotlinClass(types[it]) }
