/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found
 * in the license/LICENSE.txt file.
 */

package kotlin.native

/**
 * Exception thrown when a top-level variable is accessed from an incorrect execution context.
 */
@Deprecated("Support for the legacy memory manager has been completely removed. Usages of this exception can be safely dropped.")
@DeprecatedSinceKotlin(errorSince = "2.1")
public class IncorrectDereferenceException : RuntimeException {
    public constructor() : super()

    public constructor(message: String) : super(message)
}
