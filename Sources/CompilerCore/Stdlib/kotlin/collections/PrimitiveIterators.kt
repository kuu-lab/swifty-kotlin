/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib <libraries/stdlib/src/kotlin/collections/PrimitiveIterators.kt>.
 */

package kotlin.collections

public abstract class ByteIterator : Iterator<Byte> {
    override final fun next(): Byte = nextByte()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextByte(): Byte
}

public abstract class CharIterator : Iterator<Char> {
    override final fun next(): Char = nextChar()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextChar(): Char
}

public abstract class ShortIterator : Iterator<Short> {
    override final fun next(): Short = nextShort()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextShort(): Short
}

public abstract class IntIterator : Iterator<Int> {
    override final fun next(): Int = nextInt()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextInt(): Int
}

public abstract class LongIterator : Iterator<Long> {
    override final fun next(): Long = nextLong()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextLong(): Long
}

public abstract class FloatIterator : Iterator<Float> {
    override final fun next(): Float = nextFloat()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextFloat(): Float
}

public abstract class DoubleIterator : Iterator<Double> {
    override final fun next(): Double = nextDouble()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextDouble(): Double
}

public abstract class BooleanIterator : Iterator<Boolean> {
    override final fun next(): Boolean = nextBoolean()

    /** Returns the next value in the sequence without boxing. */
    public abstract fun nextBoolean(): Boolean
}
