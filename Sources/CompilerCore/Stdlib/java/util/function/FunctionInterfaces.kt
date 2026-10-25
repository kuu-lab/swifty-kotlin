package java.util.function

import java.util.Comparator

public fun interface Function<T, R> {
    public fun apply(value: T): R

    public companion object {
        public fun <T> identity(): Function<T, T> = Function { it }
    }
}

public fun interface Predicate<T> {
    public fun test(value: T): Boolean

    public companion object {
        public fun <T> isEqual(target: Any?): Predicate<T> = Predicate { value -> target == value }
    }
}

public fun interface Consumer<T> {
    public fun accept(value: T)
}

public fun interface Supplier<T> {
    public fun get(): T
}

public fun interface BiFunction<T, U, R> {
    public fun apply(first: T, second: U): R
}

public fun interface BiPredicate<T, U> {
    public fun test(first: T, second: U): Boolean
}

public fun interface BiConsumer<T, U> {
    public fun accept(first: T, second: U)
}

public fun interface UnaryOperator<T> : Function<T, T> {
    override public fun apply(value: T): T

    public companion object {
        public fun <T> identity(): UnaryOperator<T> = UnaryOperator { it }
    }
}

public fun interface BinaryOperator<T> : BiFunction<T, T, T> {
    override public fun apply(first: T, second: T): T

    public companion object {
        public fun <T> minBy(comparator: Comparator<in T>): BinaryOperator<T> =
            BinaryOperator { first, second -> if (comparator.compare(first, second) <= 0) first else second }

        public fun <T> maxBy(comparator: Comparator<in T>): BinaryOperator<T> =
            BinaryOperator { first, second -> if (comparator.compare(first, second) >= 0) first else second }
    }
}

public fun interface ToIntFunction<T> { public fun applyAsInt(value: T): Int }
public fun interface ToLongFunction<T> { public fun applyAsLong(value: T): Long }
public fun interface ToDoubleFunction<T> { public fun applyAsDouble(value: T): Double }
public fun interface IntFunction<R> { public fun apply(value: Int): R }
public fun interface LongFunction<R> { public fun apply(value: Long): R }
public fun interface DoubleFunction<R> { public fun apply(value: Double): R }
public fun interface IntPredicate { public fun test(value: Int): Boolean }
public fun interface LongPredicate { public fun test(value: Long): Boolean }
public fun interface DoublePredicate { public fun test(value: Double): Boolean }
public fun interface LongConsumer { public fun accept(value: Long) }
public fun interface DoubleConsumer { public fun accept(value: Double) }
public fun interface IntSupplier { public fun getAsInt(): Int }
public fun interface LongSupplier { public fun getAsLong(): Long }
public fun interface DoubleSupplier { public fun getAsDouble(): Double }
public fun interface IntUnaryOperator { public fun applyAsInt(value: Int): Int }
public fun interface LongUnaryOperator { public fun applyAsLong(value: Long): Long }
public fun interface DoubleUnaryOperator { public fun applyAsDouble(value: Double): Double }
public fun interface IntBinaryOperator { public fun applyAsInt(first: Int, second: Int): Int }
public fun interface LongBinaryOperator { public fun applyAsLong(first: Long, second: Long): Long }
public fun interface DoubleBinaryOperator { public fun applyAsDouble(first: Double, second: Double): Double }
public fun interface ObjIntConsumer<T> { public fun accept(value: T, number: Int) }
public fun interface ObjLongConsumer<T> { public fun accept(value: T, number: Long) }
public fun interface ObjDoubleConsumer<T> { public fun accept(value: T, number: Double) }
