/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 *
 * Derived from kotlinx-io core/common/src/Annotations.kt (tag 0.9.1).
 */
package kotlinx.io

/** Marks declarations that require care because misuse can corrupt or lose data. */
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@RequiresOptIn(
    level = RequiresOptIn.Level.WARNING,
    message = "This is a delicate API and its use requires care. " +
        "Make sure you fully read and understand documentation of the declaration that is marked as a delicate API."
)
public annotation class DelicateIoApi

/** Marks internal IO declarations that may change without notice. */
@MustBeDocumented
@Retention(AnnotationRetention.BINARY)
@RequiresOptIn(
    level = RequiresOptIn.Level.ERROR,
    message = "This is an internal API and its use requires care. " +
        "It is subject to change or removal and is not intended for use outside the library." +
        "Make sure you fully read and understand documentation of the declaration that " +
        "is marked as an internal API."
)
public annotation class InternalIoApi

/** Marks IO APIs whose invalid arguments may corrupt data or behave unpredictably. */
@Retention(AnnotationRetention.BINARY)
@RequiresOptIn(
    level = RequiresOptIn.Level.WARNING,
    message = "This is an unsafe API and its use requires care. " +
        "Make sure you fully understand documentation of the declaration marked as UnsafeIoApi"
)
public annotation class UnsafeIoApi
