fun main() {
    val success = Result.success(42)
    val equalSuccess = Result.success(42)
    val differentSuccess = Result.success(43)
    val successAsAny: Any = success
    val equalSuccessAsAny: Any = equalSuccess

    val exception = IllegalStateException("failure")
    val failure = Result.failure<Int>(exception)
    val equalFailure = Result.failure<Int>(exception)
    val differentFailure = Result.failure<Int>(IllegalStateException("failure"))

    println(success == equalSuccess)
    println(success.equals(equalSuccess))
    println(successAsAny == equalSuccessAsAny)
    println(success != differentSuccess)
    println(success != failure)
    println(failure == equalFailure)
    println(failure != differentFailure)
    println(success.hashCode())
    println(Result.success("abc").hashCode())
    println(Result.success<Int?>(null).hashCode())
    println(failure.hashCode() == exception.hashCode())
}
