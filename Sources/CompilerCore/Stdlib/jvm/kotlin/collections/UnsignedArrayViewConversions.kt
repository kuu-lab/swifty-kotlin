@file:kotlin.jvm.JvmName("UArraysKt")
package kotlin.collections

import kotlin.jvm.internal.__jvmReinterpret

@ExperimentalUnsignedTypes
public fun ByteArray.asUByteArray(): UByteArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun ShortArray.asUShortArray(): UShortArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun IntArray.asUIntArray(): UIntArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun LongArray.asULongArray(): ULongArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun UByteArray.asByteArray(): ByteArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun UShortArray.asShortArray(): ShortArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun UIntArray.asIntArray(): IntArray = __jvmReinterpret(this)
@ExperimentalUnsignedTypes
public fun ULongArray.asLongArray(): LongArray = __jvmReinterpret(this)
