package java.util

public class Optional<T : Any> private constructor(
    private val value: T?,
) {
    public fun get(): T = value ?: throw NoSuchElementException("No value present")

    public fun isPresent(): Boolean = value != null

    public fun isEmpty(): Boolean = value == null

    public fun orElse(other: T): T = value ?: other

    public fun orElseGet(supplier: () -> T): T = value ?: supplier()

    public fun ifPresent(action: (T) -> Unit) {
        val present = value ?: return
        action(present)
    }

    public fun filter(predicate: (T) -> Boolean): Optional<T> {
        val present = value ?: return this
        return if (predicate(present)) this else empty()
    }

    public fun <U : Any> map(mapper: (T) -> U): Optional<U> {
        val present = value ?: return empty()
        return of(mapper(present))
    }

    public override fun equals(other: Any?): Boolean =
        other is Optional<*> && value == other.value

    public override fun hashCode(): Int = value?.hashCode() ?: 0

    public override fun toString(): String =
        value?.let { "Optional[$it]" } ?: "Optional.empty"

    public companion object {
        private val emptyValue: Optional<Any> = Optional(null)

        @Suppress("UNCHECKED_CAST")
        public fun <T : Any> empty(): Optional<T> = emptyValue as Optional<T>

        public fun <T : Any> of(value: T): Optional<T> = Optional(value)

        public fun <T : Any> ofNullable(value: T?): Optional<T> =
            if (value == null) empty() else Optional(value)
    }
}
