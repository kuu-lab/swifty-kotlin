package kotlin.collections

import java.util.function.UnaryOperator

public fun <T> MutableList<T>.replaceAll(operator: UnaryOperator<T>) {
    var index = 0
    while (index < size) {
        this[index] = operator.apply(this[index])
        index++
    }
}
