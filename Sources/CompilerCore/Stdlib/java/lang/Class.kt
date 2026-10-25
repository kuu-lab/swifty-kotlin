package java.lang

import java.lang.reflect.Constructor
import java.lang.reflect.Field
import java.lang.reflect.Method
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_class_toString")
private external fun <T> __classToString(type: Class<T>): String

@KsSymbolName("__kk_assertions_enabled")
private external fun __assertionsEnabled(): kotlin.Boolean

@KsSymbolName("__kk_java_class_get_constructor")
private external fun <T> __getConstructor(
    type: Class<T>,
    parameterTypes: Array<out Class<*>>
): Constructor<T>
@KsSymbolName("__kk_class_declared_constructors")
private external fun __declaredConstructors(value: Class<*>): Array<Constructor<*>>

@KsSymbolName("__kk_class_declared_constructor")
private external fun <T> __declaredConstructor(
    value: Class<T>,
    parameterTypes: Array<out Class<*>>
): Constructor<T>
@KsSymbolName("__kk_java_class_get_declared_methods")
private external fun __classGetDeclaredMethods(type: Class<*>): Array<Method>
@KsSymbolName("__kk_class_canonical_name")
private external fun <T> __classCanonicalName(type: Class<T>): String?

@KsSymbolName("__kk_java_class_get_declared_method")
private external fun __classGetDeclaredMethod(
    type: Class<*>,
    name: String,
    parameterTypes: Array<out Class<*>>
): Method

@KsSymbolName("__kk_java_class_get_declared_field")
private external fun __classGetDeclaredField(type: Class<*>, name: String): Field

@KsSymbolName("__kk_java_class_get_name")
private external fun __classGetName(type: Class<*>): String

@KsSymbolName("__kk_class_simple_name")
private external fun __classSimpleName(type: Class<*>): String

@KsSymbolName("__kk_class_for_name")
private external fun __classForName(className: String): Class<*>

@KsSymbolName("__kk_java_class_get_annotations_typed")
private external fun __classGetAnnotations(type: Class<*>): Array<Annotation>

// JVM-shaped view of an existing class token; it does not own a ClassLoader.
public class Class<T> {
    public val canonicalName: String?
        get() = __classCanonicalName(this)

    public val classLoader: ClassLoader?
        get() = getSystemClassLoader()

    /**
     * Returns the process-wide Native assertion policy used by kotlin.assert.
     * Assertions default to disabled. KK_ASSERTIONS_ENABLED takes precedence over
     * KOTLIN_ASSERTIONS_ENABLED; neither class nor package overrides are modeled.
     */
    public fun desiredAssertionStatus(): kotlin.Boolean = __assertionsEnabled()

    /** Returns runtime-retained annotations declared on this class or inherited from its superclass. */
    public val annotations: Array<Annotation>
        get() = __classGetAnnotations(this)

    public fun getConstructor(vararg parameterTypes: Class<*>): Constructor<T> =
        __getConstructor(this, parameterTypes)
    public fun getDeclaredConstructors(): Array<Constructor<*>> = __declaredConstructors(this)

    public fun getDeclaredConstructor(vararg parameterTypes: Class<*>): Constructor<T> =
        __declaredConstructor(this, parameterTypes)

    public fun getDeclaredMethods(): Array<Method> = __classGetDeclaredMethods(this)

    public fun getDeclaredMethod(name: String, vararg parameterTypes: Class<*>): Method =
        __classGetDeclaredMethod(this, name, parameterTypes)

    /**
     * Returns an enum entry field declared by this class.
     * The native runtime panics with `java.lang.NoSuchFieldException` when the
     * name is absent or names a field outside the supported enum-entry surface.
     */
    public fun getDeclaredField(name: String): Field = __classGetDeclaredField(this, name)

    public val name: String
        get() = __classGetName(this)

    public val simpleName: String
        get() = __classSimpleName(this)

    @KsSymbolName("__kk_java_class_isInstance")
    private external fun __isInstance(value: Any?): kotlin.Boolean

    public fun isInstance(value: Any?): kotlin.Boolean = __isInstance(value)

    @KsSymbolName("__kk_class_get_enclosing_class")
    private external fun __classGetEnclosingClass(): Class<*>?

    @KsSymbolName("__kk_class_get_enclosing_constructor")
    private external fun __classGetEnclosingConstructor(): Constructor<*>?

    @KsSymbolName("__kk_class_get_enclosing_method")
    private external fun __classGetEnclosingMethod(): Method?

    @KsSymbolName("__kk_class_get_declaring_class")
    private external fun __classGetDeclaringClass(): Class<*>?

    public fun getName(): String = name

    public fun getSimpleName(): String = simpleName

    public fun getEnclosingClass(): Class<*>? = __classGetEnclosingClass()

    public fun getEnclosingConstructor(): Constructor<*>? = __classGetEnclosingConstructor()

    public fun getEnclosingMethod(): Method? = __classGetEnclosingMethod()

    public fun getDeclaringClass(): Class<*>? = __classGetDeclaringClass()

    public companion object {
        public fun forName(className: String): Class<*> = __classForName(className)
    }

    public override fun toString(): String = __classToString(this)
}
