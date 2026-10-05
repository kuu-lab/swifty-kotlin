package kotlin

// Named unary signs use the same primitive operators as +x / -x. Signed
// primitive operator syntax stays on the builtin Sema path, so these bodies
// do not recursively resolve to these declarations. Byte and Short promote
// to Int, as required by Kotlin's unary-sign contracts.

public operator fun Byte.unaryPlus(): Int = this.toInt()
public operator fun Byte.unaryMinus(): Int = -this.toInt()

public operator fun Short.unaryPlus(): Int = this.toInt()
public operator fun Short.unaryMinus(): Int = -this.toInt()

public operator fun Int.unaryPlus(): Int = this
public operator fun Int.unaryMinus(): Int = -this

public operator fun Long.unaryPlus(): Long = this
public operator fun Long.unaryMinus(): Long = -this

public operator fun Float.unaryPlus(): Float = this
public operator fun Float.unaryMinus(): Float = -this

public operator fun Double.unaryPlus(): Double = this
public operator fun Double.unaryMinus(): Double = -this
