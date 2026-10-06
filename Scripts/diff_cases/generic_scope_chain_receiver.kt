// KUU-1026: scope chains must preserve the receiver's type parameter and nullability.
class Key<T : Any>(val value: T)

class Holder {
    fun <T : Any> get(key: T): T = key
    fun <T : Any> getOrNull(key: T): T? = key
    fun <T : Any> remove(key: T) { println("remove:$key") }
    fun <T : Any> lookup(key: Key<T>): T? = key.value
}

fun <T : Any> Holder.take(key: T): T = get(key).also { remove(key) }
fun <T : Any> Holder.takeOrNull(key: T): T? = getOrNull(key).also { remove(key) }
fun <T : Any> Holder.takeSafe(key: T): T? = getOrNull(key)?.also { remove(key) }
fun <T : Any> Holder.takeKey(key: Key<T>): T? = lookup(key).also { remove(key.value) }

fun <T> T.observe(block: (T) -> Unit): T { block(this); return this }
fun <T : Any> T?.observeNonNull(block: (T) -> Unit): T? {
    if (this != null) block(this)
    return this
}

fun <T : Any> chain(value: T?): T? = value.also { println("also:$it") }
    .apply { println("apply:$this") }
    .let { it }

fun <T : Any> observe(value: T?): T? = value.observe { println("observe:$it") }
fun <T : Any> project(value: T?): T? = value.observeNonNull { println("nonNull:$it") }
fun <T : Any> safe(value: T?): T? = value?.also { println("safe:$it") }

fun main() {
    val holder = Holder()
    println(holder.take("string"))
    println(holder.take(42))
    println(holder.takeOrNull("nullable"))
    println(holder.takeSafe(7))
    println(holder.takeKey(Key("key")))
    println(chain("chain"))
    println(chain<String>(null))
    println(observe("custom"))
    println(observe<String>(null))
    println(project("project"))
    println(project<String>(null))
    println(safe("safe"))
    println(safe<String>(null))
}
