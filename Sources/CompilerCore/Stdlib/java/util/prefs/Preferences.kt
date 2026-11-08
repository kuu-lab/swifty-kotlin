package java.util.prefs

import java.util.Base64

/** An in-memory preferences tree for APIs that expect java.util.prefs.Preferences. */
public class Preferences private constructor(
    private val nodeName: String,
    private val userNode: Boolean,
    private val parentNode: Preferences?,
) {
    private val values = LinkedHashMap<String, String>()
    private val children = LinkedHashMap<String, Preferences>()
    private var removed = false

    public val name: String get() = nodeName

    public val absolutePath: String
        get() = if (parentNode == null) "/" else {
            val parentPath = parentNode?.absolutePath ?: "/"
            if (parentPath == "/") "/$nodeName" else "$parentPath/$nodeName"
        }

    public val isUserNode: Boolean get() = userNode

    public fun parent(): Preferences? = parentNode

    public fun put(key: String, value: String) {
        checkLive()
        if (key.isEmpty() || key.length > MAX_KEY_LENGTH) throw IllegalArgumentException("Invalid preference key")
        if (value.length > MAX_VALUE_LENGTH) throw IllegalArgumentException("Preference value is too long")
        values[key] = value
    }

    public fun get(key: String, defaultValue: String?): String? {
        checkLive()
        return values[key] ?: defaultValue
    }

    public fun remove(key: String) {
        checkLive()
        values.remove(key)
    }

    public fun clear() {
        checkLive()
        values.clear()
    }

    public fun putInt(key: String, value: Int) = put(key, value.toString())
    public fun getInt(key: String, defaultValue: Int): Int = get(key, null)?.toIntOrNull() ?: defaultValue
    public fun putLong(key: String, value: Long) = put(key, value.toString())
    public fun getLong(key: String, defaultValue: Long): Long = get(key, null)?.toLongOrNull() ?: defaultValue
    public fun putBoolean(key: String, value: Boolean) = put(key, value.toString())
    public fun getBoolean(key: String, defaultValue: Boolean): Boolean = get(key, null)?.toBooleanStrictOrNull() ?: defaultValue
    public fun putFloat(key: String, value: Float) = put(key, value.toString())
    public fun getFloat(key: String, defaultValue: Float): Float = get(key, null)?.toFloatOrNull() ?: defaultValue
    public fun putDouble(key: String, value: Double) = put(key, value.toString())
    public fun getDouble(key: String, defaultValue: Double): Double = get(key, null)?.toDoubleOrNull() ?: defaultValue

    public fun putByteArray(key: String, value: ByteArray) = put(key, Base64.getEncoder().encodeToString(value))

    public fun getByteArray(key: String, defaultValue: ByteArray?): ByteArray? {
        val encoded = get(key, null) ?: return defaultValue
        return try {
            Base64.getDecoder().decode(encoded)
        } catch (_: IllegalArgumentException) {
            defaultValue
        }
    }

    public fun keys(): Array<String> {
        checkLive()
        return values.keys.toTypedArray()
    }

    public fun childrenNames(): Array<String> {
        checkLive()
        return children.keys.toTypedArray()
    }

    public fun node(pathName: String): Preferences {
        checkLive()
        if (pathName.isEmpty()) return this
        var current = if (pathName.startsWith('/')) rootForThisNode() else this
        for (segment in pathName.split('/')) {
            if (segment.isEmpty() || segment == ".") continue
            if (segment == "..") {
                current = current.parentNode ?: current
                continue
            }
            if (segment.length > MAX_KEY_LENGTH) throw IllegalArgumentException("Node name is too long")
            current = current.children.getOrPut(segment) {
                Preferences(segment, userNode, current)
            }
        }
        return current
    }

    public fun nodeExists(pathName: String): Boolean {
        checkLive()
        if (pathName.isEmpty()) return true
        var current = if (pathName.startsWith('/')) rootForThisNode() else this
        for (segment in pathName.split('/')) {
            if (segment.isEmpty() || segment == ".") continue
            if (segment == "..") {
                current = current.parentNode ?: return false
                continue
            }
            current = current.children[segment] ?: return false
        }
        return true
    }

    public fun removeNode() {
        checkLive()
        val parent = parentNode ?: throw IllegalStateException("Cannot remove the root preferences node")
        parent.children.remove(nodeName)
        markRemoved()
    }

    private fun markRemoved() {
        removed = true
        values.clear()
        for (child in children.values) child.markRemoved()
        children.clear()
    }

    private fun rootForThisNode(): Preferences {
        var current = this
        while (current.parentNode != null) current = current.parentNode!!
        return current
    }

    private fun checkLive() {
        if (removed) throw IllegalStateException("Preferences node has been removed")
    }

    public fun flush() { checkLive() }

    public fun sync() { checkLive() }

    public companion object {
        private const val MAX_KEY_LENGTH = 80
        private const val MAX_VALUE_LENGTH = 8_192
        private val userRootNode = Preferences("", true, null)
        private val systemRootNode = Preferences("", false, null)

        public fun userRoot(): Preferences = userRootNode
        public fun systemRoot(): Preferences = systemRootNode

        public fun userNodeForPackage(clazz: Class<*>): Preferences =
            userRootNode.node(packagePath(clazz.name))

        public fun systemNodeForPackage(clazz: Class<*>): Preferences =
            systemRootNode.node(packagePath(clazz.name))

        private fun packagePath(className: String): String {
            val separator = className.lastIndexOf('.')
            return if (separator < 0) "/" else className.substring(0, separator)
        }
    }
}
