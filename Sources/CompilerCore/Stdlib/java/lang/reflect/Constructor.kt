package java.lang.reflect

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_java_constructor_new_instance")
private external fun <T> __newInstance(
    constructor: Constructor<T>,
    initargs: Array<out Any?>
): T

public class Constructor<T> internal constructor() {
    public fun newInstance(vararg initargs: Any?): T = __newInstance(this, initargs)
}
