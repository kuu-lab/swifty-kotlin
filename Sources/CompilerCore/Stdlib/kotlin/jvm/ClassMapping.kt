package kotlin.jvm

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass

// Keep the class token as the payload of the existing opaque Class facade.
@KsSymbolName("__kk_kclass_java")
private external fun <T : Any> __javaFromKClass(value: KClass<T>): Class<T>

// Generic extension properties use the parser's zero-argument function form.
public fun <T : Any> KClass<T>.java(): Class<T> = __javaFromKClass(this)
