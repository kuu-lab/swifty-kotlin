package java.lang

import java.lang.reflect.Constructor
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): Boolean

@KsSymbolName("__kk_class_declared_constructors")
private external fun __declaredConstructors(value: Class<*>): Array<Constructor<*>>

@KsSymbolName("__kk_class_for_name")
private external fun __classForName(className: String): Class<*>

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

    @KsSymbolName("__kk_class_get_name")
    private external fun __classGetName(): String

    @KsSymbolName("__kk_class_get_enclosing_class")
    private external fun __classGetEnclosingClass(): Class<*>?

    public fun getName(): String = __classGetName()

    public fun getEnclosingClass(): Class<*>? = __classGetEnclosingClass()

    public fun getEnclosingConstructor(): Constructor<*>? = null

    public fun getEnclosingMethod(): java.lang.reflect.Method? = null

    public fun getDeclaringClass(): Class<*>? = null

    public companion object {
        /** Resolves a JVM binary class name to its native class token. */
        public fun forName(className: String): Class<*> = __classForName(className)
    }
}
