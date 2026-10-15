package java.util

import java.lang.Class
import kotlin.internal.KsSymbolName
import kotlin.reflect.KClass
import kotlin.reflect.isInstance

// Class handles use either a reflected classifier or the Any.javaClass box.
// Only this metadata conversion is native; collection policy stays in Kotlin.
@KsSymbolName("__kk_enum_set_class")
private external fun __kkEnumSetClass(elementType: Class<*>): KClass<*>?

// Enum values are boxed ordinals at erased collection boundaries.
@KsSymbolName("kk_unbox_int")
private external fun __kkEnumSetOrdinal(element: Enum<*>): Int

/** A mutable set of one enum type, iterated in declaration order. */
public class EnumSet<E : Enum<E>> private constructor(
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
            return EnumSet<E>(elementClass)
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
