package kotlin

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_runtime_result_run_catching")
public external fun <T> runCatching(block: () -> T): Result<T>
