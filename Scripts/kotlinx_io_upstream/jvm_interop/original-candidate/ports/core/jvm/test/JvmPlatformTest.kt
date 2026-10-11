@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Use of this source code is governed by the Apache 2.0 license that can be found in the LICENSE.txt file.
 */

/*
 * Copyright (C) 2018 Square, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package kotlinx.io

import org.junit.jupiter.api.io.TempDir
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import java.lang.IllegalArgumentException
import java.nio.file.LinkOption
import java.nio.file.StandardOpenOption
import kotlin.io.path.inputStream
import kotlin.test.*

class JvmPlatformTest {
    @TempDir
    lateinit var tempDir: File

    @Test
    fun outputStreamSink() {
        val baos = ByteArrayOutputStream()
        val sink = baos.asSink()
        sink.write(Buffer().also { it.writeString("a") }, 1L)
        assertArrayEquals(baos.toByteArray(), byteArrayOf(0x61))
    }

    @Test
    fun outputStreamSinkWriteZeroBytes() {
        val baos = ByteArrayOutputStream()
        val sink = baos.asSink()
        sink.write(Buffer().also { it.writeString("a") }, 0L)
        assertEquals(0, baos.size())
    }

    @Test
    fun outputStreamSinkWriteNegativeNumberOfBytes() {
        val baos = ByteArrayOutputStream()
        val sink = baos.asSink()
        assertFailsWith<IllegalArgumentException> {
            sink.write(Buffer().also { it.writeString("a") }, -1)
        }
    }

    @Test
    fun outputStreamSinkWritePartOfTheBuffer() {
        val baos = ByteArrayOutputStream()
        val sink = baos.asSink()
        val buffer = Buffer().also { it.writeString("hello") }
        sink.write(buffer, 2)
        assertArrayEquals(baos.toByteArray(), byteArrayOf('h'.code.toByte(), 'e'.code.toByte()))
        assertEquals("llo", buffer.readString())
    }

    @Test
    fun inputStreamSource() {
        val bais = ByteArrayInputStream(byteArrayOf(0x61))
        val source = bais.asSource()
        val buffer = Buffer()
        val _ = source.readAtMostTo(buffer, 1)
        assertEquals(buffer.readString(), "a")
    }

    @Test
    fun inputStreamSourceReadZeroBytes() {
        val bais = ByteArrayInputStream(ByteArray(128))
        val source = bais.asSource()
        val buffer = Buffer()
        val _ = source.readAtMostTo(buffer, 0)
        assertEquals(0, buffer.size)
    }

    @Test
    fun inputStreamSourceReadNegativeNumberOfBytes() {
        val bais = ByteArrayInputStream(ByteArray(128))
        val source = bais.asSource()
        assertFailsWith<IllegalArgumentException> { source.readAtMostTo(Buffer(), -1) }
    }


















}
