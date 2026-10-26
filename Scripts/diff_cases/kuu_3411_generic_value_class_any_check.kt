// KUU-3411: a generic value class backed by Any? must retain both the payload
// type and nested value-class identity across constructor calls.
@JvmInline
value class Result<T>(val a: Any?)

fun main() {
    val a = Result<Int>(1)
    val b = Result<String>("sample")
    val c = Result<Result<Int>>(a)
    val d = Result<Result<Int>>(Result<Int>(1))

    val aMatches = a.a is Int
    val bMatches = b.a is String
    val cMatches = c.a is Result<*>
    val ca = c.a as Result<*>
    val caMatches = ca.a is Int
    val dMatches = d.a is Result<*>
    val da = d.a as Result<*>
    val daMatches = da.a is Int

    val aDivisor = if (aMatches) 1 else 0
    val bDivisor = if (bMatches) 1 else 0
    val cDivisor = if (cMatches) 1 else 0
    val caDivisor = if (caMatches) 1 else 0
    val dDivisor = if (dMatches) 1 else 0
    val daDivisor = if (daMatches) 1 else 0
    val aCheck = 1 / aDivisor
    val bCheck = 1 / bDivisor
    val cCheck = 1 / cDivisor
    val caCheck = 1 / caDivisor
    val dCheck = 1 / dDivisor
    val daCheck = 1 / daDivisor
}
