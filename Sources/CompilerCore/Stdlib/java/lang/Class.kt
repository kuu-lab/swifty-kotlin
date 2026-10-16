package java.lang

import java.lang.reflect.Constructor
import java.lang.reflect.Method
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_class_toString")
private external fun <T> __classToString(type: Class<T>): String

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): Boolean

@KsSymbolName("__kk_java_class_get_constructor")
private external fun <T> __getConstructor(
    type: Class<T>,
    parameterTypes: Array<out Class<*>>
): Constructor<T>
@KsSymbolName("__kk_class_declared_constructors")
private external fun __declaredConstructors(value: Class<*>): Array<Constructor<*>>

@KsSymbolName("__kk_java_class_get_declared_methods")
private external fun __classGetDeclaredMethods(type: Class<*>): Array<Method>

@KsSymbolName("__kk_class_for_name")
private external fun __classForName(className: String): Class<*>
@KsSymbolName("__kk_class_canonical_name")
private external fun <T> __classCanonicalName(type: Class<T>): String?

// JVM-shaped view of an existing class token; it does not own a ClassLoader.
public class Class<T> {
    /** Returns the JVM canonical name of this class token, or null when unavailable. */
    public val canonicalName: String?
        get() = __classCanonicalName(this)

    /**
     * Returns the native runtime's loader used for resource lookup.
     */
    public val classLoader: ClassLoader?
        get() = getSystemClassLoader()

    /**
     * Returns the process-wide Native assertion policy used by kotlin.assert.
     * Assertions default to enabled. KK_ASSERTIONS_ENABLED takes precedence over
     * KOTLIN_ASSERTIONS_ENABLED; neither class nor package overrides are modeled.
     */
    public fun desiredAssertionStatus(): Boolean = __assertionsEnabled()

    /** Returns the public constructor matching [parameterTypes]. */
    public fun getConstructor(vararg parameterTypes: Class<*>): Constructor<T> =
        __getConstructor(this, parameterTypes)
    /** Returns the constructors registered for this class token. */
    public fun getDeclaredConstructors(): Array<Constructor<*>> = __declaredConstructors(this)

    /** Returns methods declared directly by this class. */
    public fun getDeclaredMethods(): Array<Method> = __classGetDeclaredMethods(this)

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
    public override fun toString(): String = __classToString(this)
}
