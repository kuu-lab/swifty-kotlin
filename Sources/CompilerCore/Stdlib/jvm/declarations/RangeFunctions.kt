package kotlin.ranges

public infix fun Int.until(to: Int): IntRange =
    if (to == Int.MIN_VALUE) IntRange(1, 0) else IntRange(this, to - 1)

// `x in progression` resolves through the kotlin.ranges package extension
// rather than an IntProgression member, matching upstream Iterable.contains.
public operator fun IntProgression.contains(value: Int): Boolean = null!!

// `step` is an operator candidate only with the operator flag; bundled
// declarations are exempt from the legal-operator-name check the same way
// the common ProgressionConstructors.kt declaration is.
public operator infix fun IntProgression.step(step: Int): IntProgression = null!!

// Reversing swaps the endpoints and negates the step; the specialized
// progression overload keeps the IntProgression return type.
public fun IntProgression.reversed(): IntProgression = null!!

public inline fun IntRange.all(predicate: (Int) -> Boolean): Boolean {
    for (element in this) if (!predicate(element)) return false
    return true
}
