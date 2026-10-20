@file:kotlin.jvm.JvmName("Intrinsics")
package kotlin.jvm.internal

public fun areEqual(first: Any?, second: Any?): Boolean = first == second

public fun checkNotNullParameter(value: Any?, message: String?) {
    if (value == null) throw NullPointerException(message)
}

public fun checkNotNullExpressionValue(value: Any?, message: String?) {
    if (value == null) throw NullPointerException(message)
}

public fun checkParameterIsNotNull(value: Any?, message: String?) {
    if (value == null) throw NullPointerException(message)
}

public fun checkExpressionValueIsNotNull(value: Any?, message: String?) {
    if (value == null) throw NullPointerException(message)
}

public fun checkNotNull(value: Any?) { if (value == null) throw NullPointerException() }
public fun checkNotNull(value: Any?, message: String?) { if (value == null) throw NullPointerException(message) }

public fun areEqual(first: Double?, second: Double?): Boolean {
    if (first == null) return second == null
    if (second == null) return false
    val left: Double = first
    val right: Double = second
    return left == right
}

public fun areEqual(first: Double?, second: Double): Boolean {
    if (first == null) return false
    val left: Double = first
    val right: Double = second
    return left == right
}

public fun areEqual(first: Double, second: Double?): Boolean {
    if (second == null) return false
    val left: Double = first
    val right: Double = second
    return left == right
}

public fun areEqual(first: Float?, second: Float?): Boolean {
    if (first == null) return second == null
    if (second == null) return false
    val left: Float = first
    val right: Float = second
    return left == right
}

public fun areEqual(first: Float?, second: Float): Boolean {
    if (first == null) return false
    val left: Float = first
    val right: Float = second
    return left == right
}

public fun areEqual(first: Float, second: Float?): Boolean {
    if (second == null) return false
    val left: Float = first
    val right: Float = second
    return left == right
}

public fun reifiedOperationMarker(id: Int, typeParameterIdentifier: String) {
    throw UnsupportedOperationException("This function has a reified type parameter and thus can only be inlined at compilation time, not called directly.")
}
public fun reifiedOperationMarker(id: Int, typeParameterIdentifier: String, message: String) {
    throw UnsupportedOperationException(message)
}

public fun compare(first: Int, second: Int): Int = if (first < second) -1 else if (first == second) 0 else 1
public fun compare(first: Long, second: Long): Int = if (first < second) -1 else if (first == second) 0 else 1

public fun needClassReification() { throw UnsupportedOperationException("This function has a reified type parameter and can only be inlined.") }
public fun needClassReification(message: String) { throw UnsupportedOperationException(message) }

fun throwUninitializedPropertyAccessException(name: String) {
    throw kotlin.UninitializedPropertyAccessException("lateinit property $name has not been initialized")
}
