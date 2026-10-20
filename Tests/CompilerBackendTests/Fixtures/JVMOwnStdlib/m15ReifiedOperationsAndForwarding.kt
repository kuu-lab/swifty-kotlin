@JvmInline value class V(val value: Int)
inline fun <reified T> test(value: Any?): Boolean = value is T
inline fun <reified T> cast(value: Any?): T = value as T
inline fun <reified T> safe(value: Any?): T? = value as? T
inline fun <reified T: Any> klass(): kotlin.reflect.KClass<T> = T::class
inline fun <reified T> array(n: Int): Array<T?> = arrayOfNulls<T>(n)
inline fun <reified U> forward(value: Any?): Boolean = test<U>(value)
inline fun <reified U> arrayTest(value: Any?): Boolean = test<Array<U>>(value)
inline fun <reified T: Number> bounded(value: Any?): T = value as T
fun main() {
    println(test<Int>(21)); println(test<String>(21)); println(test<Int?>(null)); println(test<Int>(null))
    println(cast<Int>(21)); println(safe<Int>("wrong")); println(safe<String>("text"))
    println(klass<Int>().simpleName); println(klass<Int>().java.name); println(klass<String>().java.name)
    val a = array<String>(2); a[1] = "item"; println(a.size); println(a[1]); println(a.javaClass.name)
    println(array<Int>(1).javaClass.name); println(forward<String>("yes"))
    println(arrayTest<String>(arrayOf("yes"))); println(arrayTest<String>(arrayOf(1)))
    println(test<V>(V(7))); println(cast<V>(V(8))); println(bounded<Int>(9))
    try { cast<String>(21) } catch (e: ClassCastException) { println("cast") }
}
