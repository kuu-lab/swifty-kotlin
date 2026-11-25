/*
 * Copyright 2017-2024 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization

import kotlinx.serialization.descriptors.*

@MustBeDocumented
@Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY, AnnotationTarget.FUNCTION, AnnotationTarget.TYPEALIAS)
@RequiresOptIn(level = RequiresOptIn.Level.WARNING)
public annotation class ExperimentalSerializationApi

@MustBeDocumented
@Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY, AnnotationTarget.FUNCTION, AnnotationTarget.TYPEALIAS)
@RequiresOptIn(level = RequiresOptIn.Level.ERROR)
public annotation class InternalSerializationApi

@MustBeDocumented
@Target()
@RequiresOptIn(message = "This class or interface should not be inherited/implemented outside of kotlinx.serialization library. " +
    "Note it is still permitted to use it directly. Read its documentation about inheritance for details.", level = RequiresOptIn.Level.ERROR)
public annotation class SealedSerializationApi
