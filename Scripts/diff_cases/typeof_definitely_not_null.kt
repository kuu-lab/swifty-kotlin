// KUU-3816 (KT-77299): a definitely-non-null `T & Any` inside typeOf must
// collapse to the plain type parameter `T` instead of leaking the internal
// `java.lang.Void` classifier.
import kotlin.reflect.KType
import kotlin.reflect.typeOf

class C<T> {
    fun list(): KType = typeOf<List<T & Any>>()
    fun map(): KType = typeOf<Map<String, T & Any>>()
    fun nullableList(): KType = typeOf<List<T & Any>?>()
}

inline fun <reified R> reifiedList(): KType = typeOf<List<R & Any>>()

fun main() {
    println(C<Any>().list())
    println(C<Any>().map())
    println(C<Any>().nullableList())
    println(reifiedList<String>())
    println(reifiedList<String?>())
}
