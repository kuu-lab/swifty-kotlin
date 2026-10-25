package java.util

import kotlin.internal.KsSymbolName
import java.util.function.Supplier

// The runtime owns erased object-method pointers and their exception channel.
@KsSymbolName("__kk_objects_equals")
private external fun objectsEquals(a: Any, b: Any?): Boolean

public object Objects {
    public fun <T> compare(a: T, b: T, comparator: Comparator<in T>?): Int {
        return (comparator ?: throw NullPointerException()).compare(a, b)
    }

    public fun equals(a: Any?, b: Any?): Boolean {
        if (a === b) return true
        if (a == null || b == null) return false
        return objectsEquals(a, b)
    }

    public fun hash(vararg values: Any?): Int {
        var result = 1
        for (value in values) {
            result = 31 * result + (value?.hashCode() ?: 0)
        }
        return result
    }

    public fun toString(value: Any?): String = value?.toString() ?: "null"

    public fun toString(value: Any?, nullDefault: String?): String? = value?.toString() ?: nullDefault

    public fun <T : Any> requireNonNull(value: T?): T {
        if (value == null) throw NullPointerException()
        return value
    }

    public fun <T : Any> requireNonNull(value: T?, message: String?): T {
        if (value == null) throw NullPointerException(message)
        return value
    }

    public fun <T : Any> requireNonNull(value: T?, messageSupplier: Supplier<out String>): T {
        if (value == null) throw NullPointerException(messageSupplier.get())
        return value
    }

    public fun isNull(value: Any?): Boolean = value == null

    public fun nonNull(value: Any?): Boolean = value != null

    public fun hashCode(value: Any?): Int = value?.hashCode() ?: 0

    public fun deepEquals(a: Any?, b: Any?): Boolean {
        if (a === b) return true
        if (a == null || b == null) return false
        return deepEqualsValue(a, b)
    }

    private fun deepEqualsValue(a: Any, b: Any?): Boolean {
        if (a is Array<*> && b is Array<*>) {
            if (a.size != b.size) return false
            var index = 0
            while (index < a.size) {
                val left = a[index]
                val right = b[index]
                // Arrays.deepEquals only short-circuits a null left element;
                // a non-null element still receives equals(null) on the right.
                if (left !== right) {
                    if (left == null || !deepEqualsValue(left, right)) return false
                }
                index++
            }
            return true
        }
        if (a is ByteArray && b is ByteArray) return a.contentEquals(b)
        if (a is ShortArray && b is ShortArray) return a.contentEquals(b)
        if (a is IntArray && b is IntArray) return a.contentEquals(b)
        if (a is LongArray && b is LongArray) return a.contentEquals(b)
        if (a is CharArray && b is CharArray) return a.contentEquals(b)
        if (a is BooleanArray && b is BooleanArray) return a.contentEquals(b)
        // Java compares canonical NaN bits and distinguishes signed zero.
        if (a is FloatArray && b is FloatArray) {
            if (a.size != b.size) return false
            var index = 0
            while (index < a.size) {
                if (a[index].toBits() != b[index].toBits()) return false
                index++
            }
            return true
        }
        if (a is DoubleArray && b is DoubleArray) {
            if (a.size != b.size) return false
            var index = 0
            while (index < a.size) {
                if (a[index].toBits() != b[index].toBits()) return false
                index++
            }
            return true
        }
        // Non-arrays retain the first operand's ordinary equals dispatch.
        return objectsEquals(a, b)
    }
}
