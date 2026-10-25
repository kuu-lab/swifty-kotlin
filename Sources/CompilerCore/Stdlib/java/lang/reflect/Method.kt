package java.lang.reflect

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_java_method_get_name")
private external fun __methodGetName(method: Method): String

@KsSymbolName("__kk_java_method_is_synthetic")
private external fun __methodIsSynthetic(method: Method): kotlin.Boolean

@KsSymbolName("__kk_java_method_get_return_type")
private external fun __methodGetReturnType(method: Method): Class<*>

public class Method internal constructor() {
    public fun getName(): String = __methodGetName(this)

    public fun isSynthetic(): kotlin.Boolean = __methodIsSynthetic(this)

    public val returnType: Class<*>
        get() = __methodGetReturnType(this)
}
