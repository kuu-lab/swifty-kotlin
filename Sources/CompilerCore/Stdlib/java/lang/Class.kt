package java.lang

import java.lang.reflect.Constructor
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): Boolean

@KsSymbolName("__kk_class_declared_constructors")
private external fun __declaredConstructors(value: Class<*>): Array<Constructor<*>>

@KsSymbolName("__kk_class_canonical_name")
private external fun <T> __classCanonicalName(type: Class<T>): String?

// JVM-shaped view of an existing class token; it does not own a ClassLoader.
public class Class<T> {
    /** Returns the JVM canonical name of this class token, or null when unavailable. */
    public val canonicalName: String?
        get() = __classCanonicalName(this)

    /**
     * Returns the process-wide Native assertion policy used by kotlin.assert.
     * Assertions default to enabled. KK_ASSERTIONS_ENABLED takes precedence over
     * KOTLIN_ASSERTIONS_ENABLED; neither class nor package overrides are modeled.
     */
    public fun desiredAssertionStatus(): Boolean = __assertionsEnabled()

    /** Returns the constructors registered for this class token. */
    public fun getDeclaredConstructors(): Array<Constructor<*>> = __declaredConstructors(this)
}
