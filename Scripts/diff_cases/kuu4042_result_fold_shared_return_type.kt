// KUU-4042: Result.fold's R is shared by both transforms. It must stay open
// until both lambda bodies are analysed, so the failure transform's return
// type is not pinned by the success transform (was: KSWIFTK-SEMA-0469 on
// `it.message`, checked against the first lambda's Int).

fun main() {
    val err: Result<Int> = Result.failure(IllegalStateException("e1"))
    println(err.fold({ it + 1 }, { it.message }))
    println(err.fold(onSuccess = { it + 1 }, onFailure = { it.message }))
    val ok: Result<Int> = Result.success(3)
    println(ok.fold({ it + 1 }, { it.message }))
    // The same shared-variable shape on a user-declared generic call.
    println(myFold(3, { it + 1 }, { it.message }))
}

fun <R> myFold(x: Int, ok: (Int) -> R, fail: (Throwable) -> R): R = ok(x)
