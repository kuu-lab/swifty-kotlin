package kotlin.collections

import java.util.Enumeration
import java.util.function.UnaryOperator

public fun <T> MutableList<T>.replaceAll(operator: UnaryOperator<T>) {
    var index = 0
    while (index < size) {
        this[index] = operator.apply(this[index])
        index++
    }
}

public fun <T> Enumeration<T>.toList(): List<T> {
    val result = ArrayList<T>()
    while (hasMoreElements()) {
        result.add(nextElement())
    }
    return result
}
