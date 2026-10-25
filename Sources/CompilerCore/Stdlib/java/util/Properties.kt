package java.util

import kotlin.collections.LinkedHashSet

public class Properties : Hashtable<Any, Any>() {
    private var defaults: Properties? = null

    public constructor() : super()

    public constructor(defaults: Properties?) : super() {
        this.defaults = defaults
    }

    public fun getProperty(key: String): String? {
        val value = get(key)
        if (value is String) return value
        return defaults?.getProperty(key)
    }

    public fun getProperty(key: String, defaultValue: String): String =
        getProperty(key) ?: defaultValue

    public fun setProperty(key: String, value: String): Any? = put(key, value)

    public fun propertyNames(): Enumeration<Any> = keys()

    public fun stringPropertyNames(): kotlin.collections.Set<String> {
        val names = LinkedHashSet<String>()
        for (entry in entries) {
            val key = entry.key
            val value = entry.value
            if (key is String && value is String) names.add(key)
        }
        val inherited = defaults
        if (inherited != null) names.addAll(inherited.stringPropertyNames())
        return names
    }
}
