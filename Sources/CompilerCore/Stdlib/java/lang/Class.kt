package java.lang

import java.lang.reflect.Constructor
import java.lang.reflect.Method
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): Boolean

@KsSymbolName("__kk_class_declared_constructors")
private external fun __declaredConstructors(value: Class<*>): Array<Constructor<*>>

@KsSymbolName("__kk_java_class_get_declared_methods")
private external fun __classGetDeclaredMethods(type: Class<*>): Array<Method>

// JVM-shaped view of an existing class token; it does not own a ClassLoader.
public class Class<T> {
    /**
     * Returns the process-wide Native assertion policy used by kotlin.assert.
     * Assertions default to enabled. KK_ASSERTIONS_ENABLED takes precedence over
     * KOTLIN_ASSERTIONS_ENABLED; neither class nor package overrides are modeled.
     */
    public fun desiredAssertionStatus(): Boolean = __assertionsEnabled()

    /** Returns the constructors registered for this class token. */
    public fun getDeclaredConstructors(): Array<Constructor<*>> = __declaredConstructors(this)

    /** Returns methods declared directly by this class. */
    public fun getDeclaredMethods(): Array<Method> = __classGetDeclaredMethods(this)
}
