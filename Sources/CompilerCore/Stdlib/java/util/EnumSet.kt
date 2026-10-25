package java.util

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass
import kotlin.reflect.isInstance

// Class handles use either a reflected classifier or the Any.javaClass box.
// Only this metadata conversion is native; collection policy stays in Kotlin.
@KsSymbolName("__kk_enum_set_class")
private external fun __kkEnumSetClass(elementType: Class<*>): KClass<*>?

@KsSymbolName("__kk_enum_set_values")
private external fun <E : Enum<E>> __kkEnumSetValues(elementType: Class<E>): Array<E>?

// Enum values are boxed ordinals at erased collection boundaries.
@KsSymbolName("kk_unbox_int")
private external fun __kkEnumSetOrdinal(element: Enum<*>): Int

/** A mutable set of one enum type, iterated in declaration order. */
public class EnumSet<E : Enum<E>> private constructor(
    private val elementType: Class<E>,
    private val elementClass: KClass<*>
) : AbstractMutableSet<E>() {
    private val elements: MutableList<E> = ArrayList<E>()

    override val size: Int
        get() = elements.size

    override fun contains(element: E): Boolean =
        elementClass.isInstance(element) && elements.contains(element)

    @IgnorableReturnValue
    override fun add(element: E): Boolean {
        val value: Any? = element
        if (value == null) throw NullPointerException()
        if (!elementClass.isInstance(value)) throw ClassCastException()
        val ordinal = __kkEnumSetOrdinal(element)
        var index = 0
        while (index < elements.size) {
            val current = __kkEnumSetOrdinal(elements[index])
            if (current == ordinal) return false
            if (current > ordinal) break
            index++
        }
        elements.add(index, element)
        return true
    }

    @IgnorableReturnValue
    override fun remove(element: E): Boolean =
        elementClass.isInstance(element) && elements.remove(element)

    override fun clear() {
        elements.clear()
    }

    override fun iterator(): MutableIterator<E> = EnumSetIterator(elements, ArrayList<E>(elements))

    public companion object {
        public fun <E : Enum<E>> noneOf(elementType: Class<E>?): EnumSet<E> {
            if (elementType == null) throw NullPointerException()
            val elementClass = __kkEnumSetClass(elementType) ?: throw ClassCastException()
            return EnumSet<E>(elementType, elementClass)
        }

        public fun <E : Enum<E>> of(first: E, vararg rest: E): EnumSet<E> {
            val result = noneOf(first.javaClass)
            result.add(first)
            for (element in rest) result.add(element)
            return result
        }

        public fun <E : Enum<E>> allOf(elementType: Class<E>?): EnumSet<E> {
            val result = noneOf(elementType)
            val values = __kkEnumSetValues(elementType ?: throw NullPointerException())
                ?: throw ClassCastException()
            for (element in values) result.add(element)
            return result
        }

        public fun <E : Enum<E>> copyOf(source: EnumSet<E>?): EnumSet<E> {
            val nonNullSource = source ?: throw NullPointerException()
            val result = noneOf(nonNullSource.elementType)
            for (element in nonNullSource) result.add(element)
            return result
        }

        public fun <E : Enum<E>> copyOf(source: Collection<E>?): EnumSet<E> {
            val nonNullSource = source ?: throw NullPointerException()
            val iterator = nonNullSource.iterator()
            if (!iterator.hasNext()) throw IllegalArgumentException("Collection is empty")
            val first = iterator.next()
            val result = noneOf(first.javaClass)
            result.add(first)
            while (iterator.hasNext()) result.add(iterator.next())
            return result
        }

        public fun <E : Enum<E>> complementOf(source: EnumSet<E>?): EnumSet<E> {
            val nonNullSource = source ?: throw NullPointerException()
            val result = allOf(nonNullSource.elementType)
            for (element in nonNullSource) result.remove(element)
            return result
        }

        public fun <E : Enum<E>> range(from: E, to: E): EnumSet<E> {
            if (from.javaClass != to.javaClass) throw ClassCastException()
            if (from.ordinal > to.ordinal) throw IllegalArgumentException("fromIndex must be <= toIndex")
            val result = noneOf(from.javaClass)
            val values = __kkEnumSetValues(from.javaClass) ?: throw ClassCastException()
            for (element in values) {
                if (element.ordinal >= from.ordinal && element.ordinal <= to.ordinal) result.add(element)
            }
            return result
        }
    }
}

private class EnumSetIterator<E>(
    private val elements: MutableList<E>,
    private val snapshot: List<E>
) : MutableIterator<E> {
    // A snapshot avoids fail-fast iteration while remove still updates this set.
    private var index = 0
    private var lastIndex = -1

    override fun hasNext(): Boolean = index < snapshot.size

    override fun next(): E {
        if (!hasNext()) throw NoSuchElementException()
        lastIndex = index
        index++
        return snapshot[lastIndex]
    }

    override fun remove() {
        if (lastIndex < 0) throw IllegalStateException()
        elements.remove(snapshot[lastIndex])
        lastIndex = -1
    }
}
