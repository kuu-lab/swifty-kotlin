package kotlin

// KSP-604: `repeat` migrated from the synthetic stdlib loop stub. It stays
// `inline` so that suspend calls inside `action` remain in the enclosing suspend
// function and can be coroutine-lowered.
public inline fun repeat(times: Int, action: (Int) -> Unit) {
    var index = 0
    while (index < times) {
        action(index)
        index += 1
    }
}
