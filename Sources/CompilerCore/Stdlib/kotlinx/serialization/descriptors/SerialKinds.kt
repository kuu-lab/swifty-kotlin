/*
 * Copyright 2017-2021 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.descriptors

import kotlinx.serialization.ExperimentalSerializationApi

public sealed class SerialKind {

    public object ENUM : SerialKind()

    public object CONTEXTUAL : SerialKind()

    override fun toString(): String {
        return this::class.simpleName!!
    }

    override fun hashCode(): Int = toString().hashCode()
}

public sealed class PrimitiveKind : SerialKind() {
    public object BOOLEAN : PrimitiveKind()

    public object BYTE : PrimitiveKind()

    public object CHAR : PrimitiveKind()

    public object SHORT : PrimitiveKind()

    public object INT : PrimitiveKind()

    public object LONG : PrimitiveKind()

    public object FLOAT : PrimitiveKind()

    public object DOUBLE : PrimitiveKind()

    public object STRING : PrimitiveKind()
}

public sealed class StructureKind : SerialKind() {

    public object CLASS : StructureKind()

    public object LIST : StructureKind()

    public object MAP : StructureKind()

    public object OBJECT : StructureKind()
}

@ExperimentalSerializationApi
public sealed class PolymorphicKind : SerialKind() {
    public object SEALED : PolymorphicKind()

    public object OPEN : PolymorphicKind()
}
