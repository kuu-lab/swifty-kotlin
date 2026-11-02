/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 *
 * Derived from kotlinx.serialization core/commonMain/src/kotlinx/serialization/builtins/BuiltinSerializers.kt.
 * Only the `nullable` extension is ported; the primitive/collection/companion `serializer()`
 * factories are backed by the serialization compiler plugin and remain unported.
 */

package kotlinx.serialization.builtins

import kotlinx.serialization.*
import kotlinx.serialization.internal.*

/**
 * Returns a nullable serializer for the given serializer of non-null type.
 */
@OptIn(ExperimentalSerializationApi::class)
public val <T : Any> KSerializer<T>.nullable: KSerializer<T?>
    get() {
        @Suppress("UNCHECKED_CAST")
        return if (descriptor.isNullable) (this as KSerializer<T?>) else NullableSerializer(this)
    }
