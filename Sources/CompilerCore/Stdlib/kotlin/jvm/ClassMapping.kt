package kotlin.jvm

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass

// Convert the classifier retained by KClass into its JVM-shaped Class facade.
@KsSymbolName("__kk_kclass_java_class")
private external fun <T : Any> __javaFromKClass(value: KClass<T>): Class<T>

// Generic extension properties use the parser's zero-argument function form.
public fun <T : Any> KClass<T>.java(): Class<T> = __javaFromKClass(this)
