// EXPECT-REJECT
interface Iface {
    protected fun hidden() = "h"
    protected val value: Int get() = 1
    protected class Nested
}
