@file:Suppress("NOTHING_TO_INLINE")

package kotlin

inline fun repeat(times: Int, action: (Int) -> Unit) {
    var index = 0
    while (index < times) {
        action(index)
        index = index + 1
    }
}
