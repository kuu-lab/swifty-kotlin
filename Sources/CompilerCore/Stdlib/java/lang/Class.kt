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
@KsSymbolName("__kk_java_class_get_methods")
private external fun __classGetMethods(type: Class<*>): Array<Method>
@KsSymbolName("__kk_java_class_is_assignable_from")
private external fun __classIsAssignableFrom(type: Class<*>, other: Class<*>): Boolean
@KsSymbolName("__kk_class_canonical_name")
private external fun <T> __classCanonicalName(type: Class<T>): String?

@KsSymbolName("__kk_class_is_interface")
private external fun __classIsInterface(type: Class<*>): kotlin.Boolean

@KsSymbolName("__kk_java_class_get_declared_method")
private external fun __classGetDeclaredMethod(
    type: Class<*>,
    name: String,
    parameterTypes: Array<out Class<*>>
): Method

@KsSymbolName("__kk_java_class_get_declared_field")
private external fun __classGetDeclaredField(type: Class<*>, name: String): Field

@KsSymbolName("__kk_java_class_get_field")
private external fun __classGetField(type: Class<*>, name: String): Field

@KsSymbolName("__kk_java_class_get_modifiers")
private external fun __classGetModifiers(type: Class<*>): Int

@KsSymbolName("__kk_java_class_identity_token")
private external fun __classIdentityToken(type: Class<*>): Int

@KsSymbolName("__kk_java_class_get_name")
private external fun __classGetName(type: Class<*>): String

@KsSymbolName("__kk_class_simple_name")
private external fun __classSimpleName(type: Class<*>): String

@KsSymbolName("__kk_class_for_name")
private external fun __classForName(className: String): Class<*>

@KsSymbolName("__kk_java_class_get_annotations_typed")
private external fun __classGetAnnotations(type: Class<*>): Array<Annotation>

@KsSymbolName("__kk_class_interfaces")
private external fun __classInterfaces(type: Class<*>): Array<Class<*>>

@KsSymbolName("__kk_class_superclass")
private external fun __classSuperclass(type: Class<*>): Class<*>?

@KsSymbolName("__kk_class_is_array")
private external fun __classIsArray(type: Class<*>): kotlin.Boolean

@KsSymbolName("__kk_class_is_primitive")
private external fun __classIsPrimitive(type: Class<*>): kotlin.Boolean

@KsSymbolName("__kk_class_is_enum")
private external fun __classIsEnum(type: Class<*>): kotlin.Boolean

@KsSymbolName("__kk_class_component_type")
private external fun __classComponentType(type: Class<*>): Class<*>?

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

    public val annotations: Array<Annotation>
        get() = __classGetAnnotations(this)

    public fun getConstructor(vararg parameterTypes: Class<*>): Constructor<T> =
        __getConstructor(this, parameterTypes)
    public fun getDeclaredConstructors(): Array<Constructor<*>> = __declaredConstructors(this)

    public fun getDeclaredConstructor(vararg parameterTypes: Class<*>): Constructor<T> =
        __declaredConstructor(this, parameterTypes)

    public fun getDeclaredMethods(): Array<Method> = __classGetDeclaredMethods(this)

    public fun getMethods(): Array<Method> = __classGetMethods(this)

    public val methods: Array<Method>
        get() = __classGetMethods(this)

    public val interfaces: Array<Class<*>>
        get() = __classInterfaces(this)

    public fun getInterfaces(): Array<Class<*>> = __classInterfaces(this)

    public val superclass: Class<*>?
        get() = __classSuperclass(this)

    public fun getSuperclass(): Class<*>? = __classSuperclass(this)
    public fun isAssignableFrom(other: Class<*>): Boolean = __classIsAssignableFrom(this, other)

    public val isArray: kotlin.Boolean
        get() = __classIsArray(this)

    public val isPrimitive: kotlin.Boolean
        get() = __classIsPrimitive(this)

    public val isEnum: kotlin.Boolean
        get() = __classIsEnum(this)

    public val componentType: Class<*>?
        get() = __classComponentType(this)

    public fun getComponentType(): Class<*>? = __classComponentType(this)

    public fun getDeclaredMethod(name: String, vararg parameterTypes: Class<*>): Method =
        __classGetDeclaredMethod(this, name, parameterTypes)

    public fun getMethod(name: String, vararg parameterTypes: Class<*>): Method {
        for (method in getMethods()) {
            if (method.getName() != name) continue
            val params = method.getParameterTypes()
            if (params.size != parameterTypes.size) continue
            var match = true
            for (index in params.indices) {
                if (__classIdentityToken(params[index]) != __classIdentityToken(parameterTypes[index])) {
                    match = false
                    break
                }
            }
            if (match) return method
        }
        throw NoSuchMethodException(name)
    }

    public fun getDeclaredField(name: String): Field = __classGetDeclaredField(this, name)

    public fun getField(name: String): Field = __classGetField(this, name)

    public fun getModifiers(): Int = __classGetModifiers(this)

    @KsSymbolName("__kk_enum_set_values")
    private external fun __enumConstants(): Array<T>?

    public fun getEnumConstants(): Array<T>? = __enumConstants()

    public val name: String
        get() = __classGetName(this)

    public val simpleName: String
        get() = __classSimpleName(this)

    @KsSymbolName("__kk_java_class_isInstance")
    private external fun __isInstance(value: Any?): kotlin.Boolean

    public fun isInstance(value: Any?): kotlin.Boolean = __isInstance(value)

    public val isInterface: kotlin.Boolean
        get() = __classIsInterface(this)

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
