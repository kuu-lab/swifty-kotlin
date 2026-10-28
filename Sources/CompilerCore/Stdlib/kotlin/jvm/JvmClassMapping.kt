package kotlin.jvm

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass

// Native Class and KClass handles use runtime type tokens rather than object slots.
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

/**
 * Returns the Java class of the enum declaration that owns this entry.
 *
 * The enum value is boxed at this generic boundary, preserving its declared
 * enum type even when the entry has a class body.
 */
@Suppress("UNCHECKED_CAST")
public val <E : Enum<E>> Enum<E>.declaringJavaClass: Class<E>
    get() = this.javaClass() as Class<E>
