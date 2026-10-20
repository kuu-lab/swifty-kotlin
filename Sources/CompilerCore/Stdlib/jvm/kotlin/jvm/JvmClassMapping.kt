@file:kotlin.jvm.JvmName("JvmClassMappingKt")
package kotlin.jvm
import kotlin.jvm.internal.ClassReference
fun <T> getJavaClass(type: kotlin.reflect.KClass<T>): java.lang.Class<T> = (type as ClassReference<T>).jClass
fun <T> getKotlinClass(type: java.lang.Class<T>): kotlin.reflect.KClass<T> = ClassReference<T>(type) as kotlin.reflect.KClass<T>
