class Stack<T> {
    private val items = mutableListOf<T>()
    fun push(x: T) { items.add(x) }
    fun pop(): T = items.removeAt(items.size - 1)
    fun peek(): T? = items.lastOrNull()
    val size get() = items.size
}

class Reg<K, V> {
    private val m = mutableMapOf<K, V>()
    fun put(k: K, v: V) { m[k] = v }
    fun get(k: K): V? = m[k]
}

class Cache<K, V> {
    private val cache = HashMap<K, V>()
    fun put(k: K, v: V) { cache[k] = v }
    fun get(k: K): V? = cache[k]
}

class Nested<T> {
    private val xs = mutableListOf<List<T>>()
    fun add(l: List<T>) { xs.add(l) }
    fun first(): List<T> = xs.removeAt(0)
}

abstract class Repo<T, ID> {
    protected val store = mutableMapOf<ID, T>()
    abstract fun idOf(t: T): ID
    fun save(t: T) { store[idOf(t)] = t }
    fun find(id: ID): T? = store[id]
    fun all(): List<T> = store.values.toList()
}

data class User(val id: Int, val name: String)
class UserRepo : Repo<User, Int>() { override fun idOf(t: User) = t.id }

fun main() {
    val st = Stack<String>(); st.push("a"); st.push("b")
    println(st.peek()); println(st.pop()); println(st.size); println(st.pop()); println(st.peek())
    val r = Reg<String, Int>(); r.put("a", 1); println(r.get("a")); println(r.get("b"))
    val c = Cache<String, Int>(); c.put("x", 5); println(c.get("x")); println(c.get("y"))
    val n = Nested<Int>(); n.add(listOf(1, 2)); println(n.first())
    val repo = UserRepo(); repo.save(User(1, "ann")); repo.save(User(2, "bob")); repo.save(User(1, "ann2"))
    println(repo.find(1)); println(repo.find(3)); println(repo.all().size)
}
