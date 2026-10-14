package kotlin.jvm

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass

// Native Class and KClass handles use runtime type tokens rather than object slots.
@KsSymbolName("__kk_class_kotlin")
private external fun <T : Any> classKotlin(type: Class<T>): KClass<T>

@KsSymbolName("__kk_kclass_java_primitive_type")
private external fun <T : Any> primitiveJavaClass(type: KClass<T>): Class<T>?

/** Returns the Kotlin class corresponding to this Java class, preserving T. */
public val <T : Any> Class<T>.kotlin: KClass<T>
    get() = classKotlin(this)

/** Returns the corresponding primitive Java class, or null for non-primitive types. */
public val <T : Any> KClass<T>.javaPrimitiveType: Class<T>?
    get() = primitiveJavaClass(this)
