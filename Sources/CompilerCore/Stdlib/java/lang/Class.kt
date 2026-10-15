package java.lang

import java.lang.reflect.Method
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): Boolean

@KsSymbolName("__kk_java_class_get_declared_methods")
private external fun __classGetDeclaredMethods(type: Class<*>): Array<Method>

@KsSymbolName("__kk_java_class_get_declared_method")
private external fun __classGetDeclaredMethod(
    type: Class<*>,
    name: String,
    parameterTypes: Array<out Class<*>>
): Method

@KsSymbolName("__kk_java_class_get_name")
private external fun __classGetName(type: Class<*>): String

// JVM-shaped view of an existing class token; it does not own a ClassLoader.
public class Class<T> {
    /**
     * Returns the process-wide Native assertion policy used by kotlin.assert.
     * Assertions default to enabled. KK_ASSERTIONS_ENABLED takes precedence over
     * KOTLIN_ASSERTIONS_ENABLED; neither class nor package overrides are modeled.
     */
    public fun desiredAssertionStatus(): Boolean = __assertionsEnabled()

    /** Returns methods declared directly by this class. */
    public fun getDeclaredMethods(): Array<Method> = __classGetDeclaredMethods(this)

    /** Returns the method declared by this class with the given parameter types. */
    public fun getDeclaredMethod(name: String, vararg parameterTypes: Class<*>): Method =
        __classGetDeclaredMethod(this, name, parameterTypes)

    /** Returns the JVM name of this class. */
    public val name: String
        get() = __classGetName(this)
}
