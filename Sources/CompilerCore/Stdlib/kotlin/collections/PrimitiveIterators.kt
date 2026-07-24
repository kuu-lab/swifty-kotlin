/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/PrimitiveIterators.kt>.
 */

package kotlin.collections

/** An iterator over a sequence of values of type `Byte`. */
public abstract class ByteIterator : Iterator<Byte> {
    override final fun next(): Byte = nextByte()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextByte(): Byte
}

/** An iterator over a sequence of values of type `Char`. */
public abstract class CharIterator : Iterator<Char> {
    override final fun next(): Char = nextChar()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextChar(): Char
}

/** An iterator over a sequence of values of type `Short`. */
public abstract class ShortIterator : Iterator<Short> {
    override final fun next(): Short = nextShort()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextShort(): Short
}

/** An iterator over a sequence of values of type `Int`. */
public abstract class IntIterator : Iterator<Int> {
    override final fun next(): Int = nextInt()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextInt(): Int
}

/** An iterator over a sequence of values of type `Long`. */
public abstract class LongIterator : Iterator<Long> {
    override final fun next(): Long = nextLong()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextLong(): Long
}

/** An iterator over a sequence of values of type `Float`. */
public abstract class FloatIterator : Iterator<Float> {
    override final fun next(): Float = nextFloat()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextFloat(): Float
}

/** An iterator over a sequence of values of type `Double`. */
public abstract class DoubleIterator : Iterator<Double> {
    override final fun next(): Double = nextDouble()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextDouble(): Double
}

/** An iterator over a sequence of values of type `Boolean`. */
public abstract class BooleanIterator : Iterator<Boolean> {
    override final fun next(): Boolean = nextBoolean()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextBoolean(): Boolean
}
