package kotlin.ranges
fun Byte.coerceAtLeast(minimumValue: Byte): Byte = if (this < minimumValue) minimumValue else this
fun Byte.coerceAtMost(maximumValue: Byte): Byte = if (this > maximumValue) maximumValue else this
fun Short.coerceAtLeast(minimumValue: Short): Short = if (this < minimumValue) minimumValue else this
fun Short.coerceAtMost(maximumValue: Short): Short = if (this > maximumValue) maximumValue else this
fun Int.coerceAtLeast(minimumValue: Int): Int = if (this < minimumValue) minimumValue else this
fun Int.coerceAtMost(maximumValue: Int): Int = if (this > maximumValue) maximumValue else this
fun Long.coerceAtLeast(minimumValue: Long): Long = if (this < minimumValue) minimumValue else this
fun Long.coerceAtMost(maximumValue: Long): Long = if (this > maximumValue) maximumValue else this
fun Float.coerceAtLeast(minimumValue: Float): Float = if (this < minimumValue) minimumValue else this
fun Float.coerceAtMost(maximumValue: Float): Float = if (this > maximumValue) maximumValue else this
fun Double.coerceAtLeast(minimumValue: Double): Double = if (this < minimumValue) minimumValue else this
fun Double.coerceAtMost(maximumValue: Double): Double = if (this > maximumValue) maximumValue else this

public infix fun Int.until(to: Int): IntRange =
    if (to == Int.MIN_VALUE) IntRange(1, 0) else IntRange(this, to - 1)

public inline fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}

public interface ClosedFloatingPointRange<T : Comparable<T>> {
    public val start: T
    public val endInclusive: T
    public fun lessThanOrEquals(a: T, b: T): Boolean
    public operator fun contains(value: T): Boolean
    public fun isEmpty(): Boolean
}

public class ClosedDoubleRange(
    public override val start: Double,
    public override val endInclusive: Double
) : ClosedFloatingPointRange<Double> {
    public override fun lessThanOrEquals(a: Double, b: Double): Boolean = a <= b
    public override operator fun contains(value: Double): Boolean = value >= start && value <= endInclusive
    public override fun isEmpty(): Boolean = !(start <= endInclusive)
    override fun toString(): String = "$start..$endInclusive"
    override fun equals(other: Any?): Boolean = other is ClosedDoubleRange && (isEmpty() && other.isEmpty() || start == other.start && endInclusive == other.endInclusive)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * start.hashCode() + endInclusive.hashCode()
}

public class ClosedFloatRange(
    public override val start: Float,
    public override val endInclusive: Float
) : ClosedFloatingPointRange<Float> {
    public override fun lessThanOrEquals(a: Float, b: Float): Boolean = a <= b
    public override operator fun contains(value: Float): Boolean = value >= start && value <= endInclusive
    public override fun isEmpty(): Boolean = !(start <= endInclusive)
    override fun toString(): String = "$start..$endInclusive"
    override fun equals(other: Any?): Boolean = other is ClosedFloatRange && (isEmpty() && other.isEmpty() || start == other.start && endInclusive == other.endInclusive)
    override fun hashCode(): Int = if (isEmpty()) -1 else 31 * start.hashCode() + endInclusive.hashCode()
}

public operator fun Double.rangeTo(that: Double): ClosedFloatingPointRange<Double> = ClosedDoubleRange(this, that)
public operator fun Float.rangeTo(that: Float): ClosedFloatingPointRange<Float> = ClosedFloatRange(this, that)

public infix fun IntProgression.step(step: Int): IntProgression {
    if (step <= 0) throw IllegalArgumentException("Step must be positive, was: $step.")
    return IntProgression(this.first, this.last, step)
}
