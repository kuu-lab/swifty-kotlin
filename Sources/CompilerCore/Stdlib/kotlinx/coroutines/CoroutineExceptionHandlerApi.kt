/*
 * Copyright 2016-2024 JetBrains s.r.o. and respective authors and developers.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlinx-coroutines-core/common/src/CoroutineExceptionHandler.kt.
 */
package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

@InternalCoroutinesApi
@KsSymbolName("kk_handle_coroutine_exception")
public external fun handleCoroutineException(context: CoroutineContext, exception: Throwable)
