@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

package kotlinx.io

/**
 * Native test bridge for the JVM-only RefCountingCopyTrackerTest.
 *
 * The upstream test exercises sequential state transitions only. This adapter
 * replaces the JVM AtomicIntegerFieldUpdater mechanism while preserving the
 * values asserted by the unchanged test body; it does not claim atomicity.
 */
internal class RefCountingCopyTracker : SegmentCopyTracker() {
    private var copyCount = 0

    override val shared: Boolean
        get() = copyCount > 0

    override fun addCopy() {
        copyCount++
    }

    override fun removeCopy(): Boolean {
        if (copyCount == 0) return false
        copyCount--
        return true
    }
}
