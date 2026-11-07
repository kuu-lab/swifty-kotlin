package java.util

import java.lang.Class
import kotlin.collections.AbstractMutableMap
import kotlin.collections.MutableMap
import kotlin.collections.MutableSet

/** A map whose keys are restricted to one enum type and iterated by ordinal. */
public class EnumMap<K : Enum<K>, V> private constructor() : AbstractMutableMap<K, V>() {
    private var keyType: Class<K>? = null

    public constructor(keyType: Class<K>) : this() {
        this.keyType = keyType
    }

    public constructor(source: Map<out K, V>) : this() {
        for ((key, value) in source) put(key, value)
    }

    private val backing = TreeMap<K, V>()

    override val size: Int
        get() = backing.size

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = backing.entries

    override fun containsKey(key: K): Boolean {
        checkKey(key)
        return backing.containsKey(key)
    }

    override operator fun get(key: K): V? {
        checkKey(key)
        return backing[key]
    }

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? {
        checkKey(key)
        return backing.put(key, value)
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? {
        checkKey(key)
        return backing.remove(key)
    }

    override fun clear() {
        backing.clear()
    }

    private fun checkKey(key: K) {
        val type = keyType
        if (type != null && !type.isInstance(key)) throw ClassCastException()
    }
}
