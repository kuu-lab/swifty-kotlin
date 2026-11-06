package java.util

import java.lang.Runnable
import java.util.function.Consumer
import java.util.function.Function
import java.util.function.Predicate
import java.util.function.Supplier
import java.util.stream.Stream

public class Optional<T : Any> private constructor(
    private val value: T?,
) {
    public fun get(): T = value ?: throw NoSuchElementException("No value present")

    public fun isPresent(): Boolean = value != null

    public fun isEmpty(): Boolean = value == null

    public fun ifPresent(action: Consumer<T>) {
        val present = value ?: return
        action.accept(present)
    }

    public fun ifPresentOrElse(action: Consumer<T>, emptyAction: Runnable) {
        val present = value
        if (present == null) {
            emptyAction.run()
        } else {
            action.accept(present)
        }
    }

    public fun filter(predicate: Predicate<T>): Optional<T> {
        val present = value ?: return this
        return if (predicate.test(present)) this else empty()
    }

    public fun <U : Any> map(mapper: Function<T, U>): Optional<U> {
        val present = value ?: return empty()
        return ofNullable(mapper.apply(present))
    }

    public fun <U : Any> flatMap(mapper: Function<T, Optional<U>>): Optional<U> {
        val present = value ?: return empty()
        return mapper.apply(present)
    }

    public fun or(supplier: Supplier<Optional<T>>): Optional<T> =
        if (value == null) supplier.get() else this

    public fun orElse(other: T): T = value ?: other

    public fun orElseGet(supplier: Supplier<T>): T = value ?: supplier.get()

    public fun orElseThrow(): T = get()

    public fun <X : Throwable> orElseThrow(exceptionSupplier: Supplier<X>): T =
        value ?: throw exceptionSupplier.get()

    public fun stream(): Stream<T> {
        val present = value ?: return Stream.empty()
        return Stream.of(present)
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
