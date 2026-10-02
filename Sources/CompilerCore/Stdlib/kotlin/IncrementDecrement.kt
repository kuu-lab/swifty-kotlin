package kotlin

// Explicit `inc()` / `dec()` member calls on numeric primitives (`5.inc()`, `x?.dec()`).
// The `++` / `--` operators on these types never reach these declarations: Sema keeps them
// on the builtin compound-assign path (see `inferIncrementDecrementIfNeeded`) so hot loops
// stay a plain add and Byte / Short / UByte / UShort results are wrapped to their width.
// `Char.inc()` / `Char.dec()` live in `kotlin.text` (CharConversions.kt).

public operator fun Int.inc(): Int = this + 1
public operator fun Int.dec(): Int = this - 1

public operator fun Long.inc(): Long = this + 1L
public operator fun Long.dec(): Long = this - 1L

public operator fun Byte.inc(): Byte = (this + 1).toByte()
public operator fun Byte.dec(): Byte = (this - 1).toByte()

public operator fun Short.inc(): Short = (this + 1).toShort()
public operator fun Short.dec(): Short = (this - 1).toShort()

public operator fun Float.inc(): Float = this + 1.0f
public operator fun Float.dec(): Float = this - 1.0f

public operator fun Double.inc(): Double = this + 1.0
public operator fun Double.dec(): Double = this - 1.0

public operator fun UInt.inc(): UInt = this + 1u
public operator fun UInt.dec(): UInt = this - 1u

public operator fun ULong.inc(): ULong = this + 1uL
public operator fun ULong.dec(): ULong = this - 1uL

public operator fun UByte.inc(): UByte = (this.toUInt() + 1u).toUByte()
public operator fun UByte.dec(): UByte = (this.toUInt() - 1u).toUByte()

public operator fun UShort.inc(): UShort = (this.toUInt() + 1u).toUShort()
public operator fun UShort.dec(): UShort = (this.toUInt() - 1u).toUShort()
