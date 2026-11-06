package platform.Foundation

/**
 * Typed facade over NSUserDefaults. Scalar getters mirror the real Foundation
 * defaults (missing keys read as false/0/0.0); `objectForKey` returns Kotlin
 * natives for plist scalars and collections, and wraps opaque Foundation
 * objects (NSDate/NSData/NSURL/…) back into their Kotlin facades.
 */
public open class NSUserDefaults internal constructor(handle: Long) : NSObject(handle) {
    /** initWithSuiteName:; a null suite name selects the standard defaults. */
    public constructor(suiteName: String?) : this(
        if (suiteName == null) __foundation_defaults_standard()
        else __foundation_defaults_create_suite(suiteName))

    public fun objectForKey(defaultName: String): Any? =
        __foundation_plist_unwrap(__foundation_defaults_object_for_key(__handle, defaultName))

    public fun stringForKey(defaultName: String): String? =
        __foundation_defaults_string_for_key(__handle, defaultName)

    public fun boolForKey(defaultName: String): Boolean =
        __foundation_defaults_bool_for_key(__handle, defaultName)

    public fun integerForKey(defaultName: String): Long =
        __foundation_defaults_integer_for_key(__handle, defaultName)

    public fun doubleForKey(defaultName: String): Double =
        __foundation_defaults_double_for_key(__handle, defaultName)

    public fun floatForKey(defaultName: String): Float =
        __foundation_defaults_float_for_key(__handle, defaultName)

    public fun setObject(value: Any?, forKey: String): Unit =
        __foundation_defaults_set_object(__handle, value, forKey)

    public fun setBool(value: Boolean, forKey: String): Unit =
        __foundation_defaults_set_bool(__handle, value, forKey)

    public fun setInteger(value: Long, forKey: String): Unit =
        __foundation_defaults_set_integer(__handle, value, forKey)

    public fun setDouble(value: Double, forKey: String): Unit =
        __foundation_defaults_set_double(__handle, value, forKey)

    public fun setFloat(value: Float, forKey: String): Unit =
        __foundation_defaults_set_float(__handle, value, forKey)

    public fun removeObjectForKey(defaultName: String): Unit =
        __foundation_defaults_remove_object_for_key(__handle, defaultName)

    public fun synchronize(): Boolean = __foundation_defaults_synchronize(__handle)

    public fun dictionaryRepresentation(): Map<Any?, Any?> =
        __foundation_plist_map_unwrap(__foundation_defaults_dictionary_representation(__handle))

    @Suppress("UNCHECKED_CAST")
    public fun persistentDomainForName(domainName: String): Map<Any?, Any?>? =
        (__foundation_defaults_persistent_domain_for_name(__handle, domainName) as? Map<Any?, Any?>)
            ?.let(::__foundation_plist_map_unwrap)

    public fun setPersistentDomain(domain: Map<Any?, Any?>, forName domainName: String): Unit =
        __foundation_defaults_set_persistent_domain(__handle, domain, domainName)

    public fun removePersistentDomainForName(domainName: String): Unit =
        __foundation_defaults_remove_persistent_domain_for_name(__handle, domainName)

    public fun registerDefaults(registrationDictionary: Map<Any?, Any?>): Unit =
        __foundation_defaults_register_defaults(__handle, registrationDictionary)

    public fun volatileDomainNames(): List<String> =
        __foundation_defaults_volatile_domain_names(__handle)

    public fun persistentDomainNames(): List<String> =
        __foundation_defaults_persistent_domain_names(__handle)

    public fun objectIsForcedForKey(key: String): Boolean =
        __foundation_defaults_object_is_forced_for_key(__handle, key)

    public companion object {}
}

public val NSUserDefaults.Companion.standardUserDefaults: NSUserDefaults
    get() = NSUserDefaults(__foundation_defaults_standard())

/**
 * Tagged foreign-resource tokens surface as `Long`; probe resolves the bare
 * token so genuine plist integers pass through untouched.
 */
internal fun __foundation_plist_unwrap(raw: Any?): Any? {
    if (raw is Long) {
        val token = __foundation_object_probe(raw)
        if (token >= 0L) return __wrapFoundation(token)
    }
    return raw
}

internal fun __foundation_plist_map_unwrap(raw: Any?): Map<Any?, Any?> {
    @Suppress("UNCHECKED_CAST")
    val map = raw as? Map<Any?, Any?> ?: emptyMap()
    return map.mapValues { (_, value) -> __foundation_plist_unwrap(value) }
}
