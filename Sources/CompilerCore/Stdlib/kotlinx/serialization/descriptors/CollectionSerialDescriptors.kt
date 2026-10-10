/*
 * Copyright 2017-2020 JetBrains s.r.o. Use of this source code is governed by the Apache 2.0 license.
 */

package kotlinx.serialization.descriptors

import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.internal.ArrayListClassDesc
import kotlinx.serialization.internal.HashMapClassDesc
import kotlinx.serialization.internal.HashSetClassDesc

@ExperimentalSerializationApi
public fun listSerialDescriptor(elementDescriptor: SerialDescriptor): SerialDescriptor = ArrayListClassDesc(elementDescriptor)

@ExperimentalSerializationApi
public fun mapSerialDescriptor(keyDescriptor: SerialDescriptor, valueDescriptor: SerialDescriptor): SerialDescriptor =
    HashMapClassDesc(keyDescriptor, valueDescriptor)

@ExperimentalSerializationApi
public fun setSerialDescriptor(elementDescriptor: SerialDescriptor): SerialDescriptor = HashSetClassDesc(elementDescriptor)
