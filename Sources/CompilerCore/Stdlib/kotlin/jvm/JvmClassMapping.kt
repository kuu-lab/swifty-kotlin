package kotlin.jvm

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass

@KsSymbolName("__kk_class_kotlin")
private external fun <T : Any> classKotlin(type: Class<T>): KClass<T>

@KsSymbolName("__kk_kclass_java_primitive_type")
private external fun <T : Any> primitiveJavaClass(type: KClass<T>): Class<T>?

@KsSymbolName("__kk_kclass_java_object_type")
private external fun <T : Any> objectJavaClass(type: KClass<T>): Class<T>

public val <T : Any> Class<T>.kotlin: KClass<T>
    get() = classKotlin(this)

public val <T : Any> KClass<T>.javaPrimitiveType: Class<T>?
    get() = primitiveJavaClass(this)

public val <T : Any> KClass<T>.javaObjectType: Class<T>
    get() = objectJavaClass(this)

@Suppress("UNCHECKED_CAST")
public val <E : Enum<E>> Enum<E>.declaringJavaClass: Class<E>
    get() = this.javaClass() as Class<E>
