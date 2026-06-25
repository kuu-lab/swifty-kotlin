package kotlin

// MIGRATION-RESULT-001: Result class and runCatching migrated to Kotlin source.
//
// At runtime, all method bodies are bypassed:
//   - HeaderHelpers+SyntheticResultStubs.swift sets externalLinkName on the isSuccess and
//     isFailure properties so those call sites dispatch directly to kk_result_isSuccess /
//     kk_result_isFailure.
//   - Member function stubs (getOrNull, getOrDefault, getOrElse, getOrThrow, map, fold,
//     onSuccess, onFailure, recover, …) create synthetic symbols that route every call site
//     to the corresponding kk_result_* runtime ABI functions.
//   - runCatching is bundled as a top-level source definition; the synthetic stub registered
//     first provides externalLinkName = "kk_runCatching" so actual dispatch goes to the
//     Swift runtime. The source body below is compiled but never invoked.
//
// NOTE: The class declaration cannot be placed in the bundled source because synthetic stubs
// register the Result class before header collection runs, which would produce a duplicate-
// declaration error. This file serves as the canonical Kotlin-source reference for the API.

public class Result<T> {

    val isSuccess: Boolean get() = false   // kk_result_isSuccess
    val isFailure: Boolean get() = false   // kk_result_isFailure

    fun getOrNull(): T? = null                                          // kk_result_getOrNull
    fun getOrDefault(defaultValue: T): T = defaultValue                // kk_result_getOrDefault
    fun getOrElse(onFailure: (Throwable) -> T): T = throw RuntimeException()  // kk_result_getOrElse
    fun getOrThrow(): T = throw RuntimeException()                     // kk_result_getOrThrow

    fun <R> map(transform: (T) -> R): Result<R> = throw RuntimeException()    // kk_result_map
    fun <R> fold(onSuccess: (T) -> R, onFailure: (Throwable) -> R): R = throw RuntimeException()  // kk_result_fold
    fun onSuccess(action: (T) -> Unit): Result<T> = this              // kk_result_onSuccess
    fun onFailure(action: (Throwable) -> Unit): Result<T> = this      // kk_result_onFailure
}

public fun <T> runCatching(block: () -> T): Result<T> = throw RuntimeException()  // kk_runCatching
