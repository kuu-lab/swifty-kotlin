// DIFF_CANDIDATE_ONLY: exercises the internal Uuid.generateV7(clock) seam
// through the shared stdlib artifact; the file-level INVISIBLE_MEMBER /
// INVISIBLE_REFERENCE suppression below authorizes that module-boundary access.
// DIFF_EXPECT_STDOUT: same-ms increasing: true
// DIFF_EXPECT_STDOUT: same-ms counter steps of 1: true
// DIFF_EXPECT_STDOUT: same-ms timestamp kept: true
// DIFF_EXPECT_STDOUT: regression increasing: true
// DIFF_EXPECT_STDOUT: regression steps of 1: true
// DIFF_EXPECT_STDOUT: regression timestamp pinned: true
// DIFF_EXPECT_STDOUT: rollover increasing: true
// DIFF_EXPECT_STDOUT: rollover bumped timestamp: true
// DIFF_EXPECT_STDOUT: forward timestamp: true
// DIFF_EXPECT_STDOUT: done
@file:OptIn(kotlin.uuid.ExperimentalUuidApi::class, kotlin.time.ExperimentalTime::class)
// The internal companion member lives in the stdlib artifact; suppress the
// stdlib module-boundary check for this file only.
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlin.time.Clock
import kotlin.time.Instant
import kotlin.uuid.Uuid

private class SettableClock(private var millis: Long) : Clock {
    fun setMillis(value: Long) { millis = value }
    override fun now(): Instant = Instant.fromEpochMilliseconds(millis)
}

private fun msbOf(uuid: Uuid): Long = uuid.toLongs { msb, _ -> msb }
private fun timestampOf(uuid: Uuid): Long = msbOf(uuid) ushr 16

fun main() {
    // The monotonic state is process-wide, so the fixed timestamps below are
    // kept strictly ascending across blocks.

    // Same millisecond: each call increments the 12-bit counter by exactly 1.
    val fixed = SettableClock(1_000_000L)
    val a = Uuid.generateV7(fixed)
    val b = Uuid.generateV7(fixed)
    val c = Uuid.generateV7(fixed)
    println("same-ms increasing: ${a < b && b < c}")
    println("same-ms counter steps of 1: ${msbOf(b) - msbOf(a) == 1L && msbOf(c) - msbOf(b) == 1L}")
    println("same-ms timestamp kept: ${timestampOf(c) == 1_000_000L}")

    // Clock regression: the newest observed timestamp is pinned and the
    // counter keeps incrementing instead of going backwards.
    val regress = SettableClock(2_000_000L)
    val r1 = Uuid.generateV7(regress)
    regress.setMillis(1_999_000L)
    val r2 = Uuid.generateV7(regress)
    regress.setMillis(1_998_000L)
    val r3 = Uuid.generateV7(regress)
    println("regression increasing: ${r1 < r2 && r2 < r3}")
    println("regression steps of 1: ${msbOf(r2) - msbOf(r1) == 1L && msbOf(r3) - msbOf(r2) == 1L}")
    println("regression timestamp pinned: ${timestampOf(r3) == 2_000_000L}")

    // Counter rollover: the counter seeds into [0x7000, 0x77FF], so 2049-4096
    // same-ms calls exhaust it; 5001 calls force 1 or 2 timestamp bumps of
    // exactly 1ms each.
    val rollover = SettableClock(3_000_000L)
    var prev = Uuid.generateV7(rollover)
    var increasing = true
    repeat(5000) {
        val next = Uuid.generateV7(rollover)
        if (next <= prev) increasing = false
        prev = next
    }
    val rolledMs = timestampOf(prev)
    println("rollover increasing: $increasing")
    println("rollover bumped timestamp: ${rolledMs > 3_000_000L && rolledMs <= 3_000_002L}")

    // A newer clock value resumes normal timestamp advance.
    val forward = SettableClock(4_000_000L)
    val f = Uuid.generateV7(forward)
    println("forward timestamp: ${timestampOf(f) == 4_000_000L}")
    println("done")
}
