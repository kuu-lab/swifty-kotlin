package kotlin.ranges

// MIGRATION-RANGE-003
// coerceIn / coerceAtLeast / coerceAtMost migrated to Kotlin source for
// Int, Long, Double, Float.
//
// NOTE: CallLowerer dispatch (kk_int_coerceIn etc.) is intentionally kept as
// bridge compatibility helpers while stdlib-source dispatch is rolled out
// incrementally. These lightweight bodies provide canonical type definitions
// for Sema without adding the full control-flow implementation to every
// CompilerCore test run.

public fun Int.coerceIn(minimumValue: Int, maximumValue: Int): Int = this
public fun Int.coerceAtLeast(minimumValue: Int): Int = this
public fun Int.coerceAtMost(maximumValue: Int): Int = this

public fun Long.coerceIn(minimumValue: Long, maximumValue: Long): Long = this
public fun Long.coerceAtLeast(minimumValue: Long): Long = this
public fun Long.coerceAtMost(maximumValue: Long): Long = this

public fun Double.coerceIn(minimumValue: Double, maximumValue: Double): Double = this
public fun Double.coerceAtLeast(minimumValue: Double): Double = this
public fun Double.coerceAtMost(maximumValue: Double): Double = this

public fun Float.coerceIn(minimumValue: Float, maximumValue: Float): Float = this
public fun Float.coerceAtLeast(minimumValue: Float): Float = this
public fun Float.coerceAtMost(maximumValue: Float): Float = this
