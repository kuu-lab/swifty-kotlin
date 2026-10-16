package java.lang.reflect

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_java_method_get_name")
private external fun __methodGetName(method: Method): String

@KsSymbolName("__kk_java_method_is_synthetic")
private external fun __methodIsSynthetic(method: Method): Boolean

/** JVM-shaped method metadata returned by java.lang.Class reflection. */
public class Method internal constructor() {
    public fun getName(): String = __methodGetName(this)

    public fun isSynthetic(): Boolean = __methodIsSynthetic(this)
}
