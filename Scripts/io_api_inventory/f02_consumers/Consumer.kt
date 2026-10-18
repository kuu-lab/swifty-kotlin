// IO-GATE consumer fixture (ledger and generator retired); edit by hand.
@file:OptIn(
    kotlinx.io.DelicateIoApi::class,
    kotlinx.io.InternalIoApi::class,
    kotlinx.io.UnsafeIoApi::class,
    kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class,
    kotlin.ExperimentalUnsignedTypes::class,
    kotlin.contracts.ExperimentalContracts::class,
)
package f02consumer
import f02ledger.*
import kotlinx.io.*
import kotlinx.io.files.*
import kotlinx.io.bytestring.*
import kotlinx.io.unsafe.*
import kotlinx.io.bytestring.unsafe.*
import kotlin.io.encoding.*
import kotlin.time.*
import kotlin.text.*


private var callbacks = 0
private fun seed(): Buffer = Buffer().apply { write(byteArrayOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16)) }
private fun observe(value: Any?): String = when (value) {
    null -> "null"
    is Buffer -> "Buffer:" + value.size + ":" + value.snapshot().toHexString()
    is ByteString -> "ByteString:" + value.toHexString()
    is ByteArray -> "ByteArray:" + value.joinToString(",")
    is Path -> "Path:" + value.toString()
    is FileMetadata -> "FileMetadata:" + value.isRegularFile + ":" + value.isDirectory + ":" + value.size
    is Throwable -> "Throwable:" + exceptionType(value) + ":" + value.message
    is String -> "String:" + value
    is StringBuilder -> "StringBuilder:" + value.toString()
    is List<*> -> "List:" + value.joinToString(",") { observe(it) }
    is Char -> "Char:" + value.code
    is Boolean -> "Boolean:" + value
    is Byte -> "Byte:" + value
    is Short -> "Short:" + value
    is Int -> "Int:" + value
    is Long -> "Long:" + value
    is Float -> "FloatBits:" + value.toRawBits()
    is Double -> "DoubleBits:" + value.toRawBits()
    is UByte -> "UByte:" + value
    is UShort -> "UShort:" + value
    is UInt -> "UInt:" + value
    is ULong -> "ULong:" + value
    is Unit -> "Unit"
    is Source -> "Source"
    is Sink -> "Sink"
    is RawSource -> "RawSource"
    is RawSink -> "RawSink"
    is FileSystem -> "FileSystem"
    is Segment -> "Segment"
    is SegmentReadContext -> "SegmentReadContext"
    is SegmentWriteContext -> "SegmentWriteContext"
    is BufferIterationContext -> "BufferIterationContext"
    is ByteStringBuilder -> "ByteStringBuilder:" + value.toByteString().toHexString()
    else -> "other:" + value::class.simpleName
}
private fun exceptionType(failure: Throwable): String = when (failure) {
    is EOFException -> "EOFException"
    is IOException -> "IOException"
    is IndexOutOfBoundsException -> "IndexOutOfBoundsException"
    is NumberFormatException -> "NumberFormatException"
    is IllegalArgumentException -> "IllegalArgumentException"
    is IllegalStateException -> "IllegalStateException"
    is UnsupportedOperationException -> "UnsupportedOperationException"
    else -> "other:" + failure::class.simpleName
}

private fun run_klib_001cc19c43da51fc() {
    callbacks = 0
    println("BEGIN:klib-001cc19c43da51fc")
    try {
        val target: Source = seed()
        val input0: Byte = 1.toByte()
        val input1: Long = 0L
        val input2: Long = 2L
        try {
            f01_klib_001cc19c43da51fc(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-001cc19c43da51fc")
}

private fun run_klib_00fa8d5d9f11e43f() {
    callbacks = 0
    println("BEGIN:klib-00fa8d5d9f11e43f")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_00fa8d5d9f11e43f(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-00fa8d5d9f11e43f")
}

private fun run_klib_0232231390a7139a() {
    callbacks = 0
    println("BEGIN:klib-0232231390a7139a")
    try {
        val target: kotlinx.io.Sink = Buffer()
        try {
            f01_klib_0232231390a7139a(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0232231390a7139a")
}

private fun run_klib_02a8d87ce59d3a09() {
    callbacks = 0
    println("BEGIN:klib-02a8d87ce59d3a09")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_02a8d87ce59d3a09(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-02a8d87ce59d3a09")
}

private fun run_klib_02d81927a9ec9ccf() {
    callbacks = 0
    println("BEGIN:klib-02d81927a9ec9ccf")
    try {
        val target: kotlinx.io.RawSink = Buffer()
        val input0: Buffer = seed()
        val input1: Long = 2L
        try {
            f01_klib_02d81927a9ec9ccf(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-02d81927a9ec9ccf")
}

private fun run_klib_02fc8b652c26a1a7() {
    callbacks = 0
    println("BEGIN:klib-02fc8b652c26a1a7")
    try {
        try {
            f01_klib_02fc8b652c26a1a7()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-02fc8b652c26a1a7")
}

private fun run_klib_06ddbce68f82e23e() {
    callbacks = 0
    println("BEGIN:klib-06ddbce68f82e23e")
    try {
        val target: Buffer = seed()
        try {
            f01_klib_06ddbce68f82e23e(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-06ddbce68f82e23e")
}

private fun run_klib_07506d12f1446693() {
    callbacks = 0
    println("BEGIN:klib-07506d12f1446693")
    try {
        val target: kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations = UnsafeByteStringOperations
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        try {
            f01_klib_07506d12f1446693(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-07506d12f1446693")
}

private fun run_klib_07536a2b0690464c() {
    callbacks = 0
    println("BEGIN:klib-07536a2b0690464c")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: SegmentReadContext = context
            val input0: Segment = segment!!
            val input1: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Unit = { arg0, arg1, arg2 -> callbacks++; Unit }
            try {
                f01_klib_07536a2b0690464c(target, input0, input1)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-07536a2b0690464c")
}

private fun run_klib_07cfd563616534cf() {
    callbacks = 0
    println("BEGIN:klib-07cfd563616534cf")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_07cfd563616534cf(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-07cfd563616534cf")
}

private fun run_klib_07f0c52e055ab60c() {
    callbacks = 0
    println("BEGIN:klib-07f0c52e055ab60c")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: StringBuilder = StringBuilder()
        val input2: Int = 0
        val input3: Int = 2
        try {
            f01_klib_07f0c52e055ab60c(input0, input1, input2, input3)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
            println("state:input3:" + observe(input3))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-07f0c52e055ab60c")
}

private fun run_klib_0947c0d50c4105d0() {
    callbacks = 0
    println("BEGIN:klib-0947c0d50c4105d0")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: Int = 0
        try {
            f01_klib_0947c0d50c4105d0(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0947c0d50c4105d0")
}

private fun run_klib_09c8df007d615f43() {
    callbacks = 0
    println("BEGIN:klib-09c8df007d615f43")
    try {
        try {
            f01_klib_09c8df007d615f43()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-09c8df007d615f43")
}

private fun run_klib_09d1def54614dacd() {
    callbacks = 0
    println("BEGIN:klib-09d1def54614dacd")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        try {
            f01_klib_09d1def54614dacd(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-09d1def54614dacd")
}

private fun run_klib_0b464ce5d17138e9() {
    callbacks = 0
    println("BEGIN:klib-0b464ce5d17138e9")
    try {
        val target: kotlinx.io.Sink = Buffer()
        try {
            f01_klib_0b464ce5d17138e9(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0b464ce5d17138e9")
}

private fun run_klib_0d3d6a9bd110e684() {
    callbacks = 0
    println("BEGIN:klib-0d3d6a9bd110e684")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_0d3d6a9bd110e684(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0d3d6a9bd110e684")
}

private fun run_klib_0e4b69482e6a968a() {
    callbacks = 0
    println("BEGIN:klib-0e4b69482e6a968a")
    try {
        val target: Sink = Buffer()
        val input0: Float = 1.25f
        try {
            f01_klib_0e4b69482e6a968a(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0e4b69482e6a968a")
}

private fun run_klib_0e938793c50b37d6() {
    callbacks = 0
    println("BEGIN:klib-0e938793c50b37d6")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_0e938793c50b37d6(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0e938793c50b37d6")
}

private fun run_klib_0f0ae6b0e4f74922() {
    callbacks = 0
    println("BEGIN:klib-0f0ae6b0e4f74922")
    try {
        try {
            f01_klib_0f0ae6b0e4f74922()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-0f0ae6b0e4f74922")
}

private fun run_klib_11be017879adb524() {
    callbacks = 0
    println("BEGIN:klib-11be017879adb524")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_11be017879adb524(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-11be017879adb524")
}

private fun run_klib_122a0905894ba00e() {
    callbacks = 0
    println("BEGIN:klib-122a0905894ba00e")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->
            context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())
            val target: kotlinx.io.unsafe.SegmentWriteContext = context
            val input0: Segment = segment!!
            val input1: Int = 0
            val input2: Byte = 1.toByte()
            val input3: Byte = 2.toByte()
            val input4: Byte = 3.toByte()
            val input5: Byte = 4.toByte()
            try {
                f01_klib_122a0905894ba00e(target, input0, input1, input2, input3, input4, input5)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
                println("state:input1:" + observe(input1))
                println("state:input2:" + observe(input2))
                println("state:input3:" + observe(input3))
                println("state:input4:" + observe(input4))
                println("state:input5:" + observe(input5))
            }
        4
    }
    println("committed:" + observe(contextBuffer))
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-122a0905894ba00e")
}

private fun run_klib_13c0b806a778aa5c() {
    callbacks = 0
    println("BEGIN:klib-13c0b806a778aa5c")
    try {
        val target: Source = seed()
        try {
            f01_klib_13c0b806a778aa5c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-13c0b806a778aa5c")
}

private fun run_klib_1481c81e0f5a5cc4() {
    callbacks = 0
    println("BEGIN:klib-1481c81e0f5a5cc4")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: (SegmentReadContext, Segment) -> Int = { arg0, arg1 -> callbacks++; 0 }
        try {
            f01_klib_1481c81e0f5a5cc4(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-1481c81e0f5a5cc4")
}

private fun run_klib_14f4f1842013a782() {
    callbacks = 0
    println("BEGIN:klib-14f4f1842013a782")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 0
        val input3: Int = 2
        try {
            f01_klib_14f4f1842013a782(target, input0, input1, input2, input3)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
            println("state:input3:" + observe(input3))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-14f4f1842013a782")
}

private fun run_klib_14fecc4710ddf96c() {
    callbacks = 0
    println("BEGIN:klib-14fecc4710ddf96c")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: (context: BufferIterationContext, head: Segment?) -> Unit = { arg0, arg1 -> callbacks++; Unit }
        try {
            f01_klib_14fecc4710ddf96c(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-14fecc4710ddf96c")
}

private fun run_klib_18109e8ba4982d6c() {
    callbacks = 0
    println("BEGIN:klib-18109e8ba4982d6c")
    try {
        val target: Source = seed()
        try {
            f01_klib_18109e8ba4982d6c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-18109e8ba4982d6c")
}

private fun run_klib_1884b30ae2cabdd7() {
    callbacks = 0
    println("BEGIN:klib-1884b30ae2cabdd7")
    try {
        val target: Source = seed()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_1884b30ae2cabdd7(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-1884b30ae2cabdd7")
}

private fun run_klib_191223f6c4e76860() {
    callbacks = 0
    println("BEGIN:klib-191223f6c4e76860")
    try {
        val target: Source = seed()
        val input0: Long = 2L
        try {
            f01_klib_191223f6c4e76860(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-191223f6c4e76860")
}

private fun run_klib_19a692d1a743b95e() {
    callbacks = 0
    println("BEGIN:klib-19a692d1a743b95e")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        val input1: Boolean = false
        try {
            f01_klib_19a692d1a743b95e(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-19a692d1a743b95e")
}

private fun run_klib_1cea0040ddde9cf5() {
    callbacks = 0
    println("BEGIN:klib-1cea0040ddde9cf5")
    try {
        try {
            f01_klib_1cea0040ddde9cf5()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-1cea0040ddde9cf5")
}

private fun run_klib_1d66584f002fd45f() {
    callbacks = 0
    println("BEGIN:klib-1d66584f002fd45f")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: kotlinx.io.Segment = segment!!
            try {
                f01_klib_1d66584f002fd45f(target)
            } finally {
                println("state:target:" + observe(target))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-1d66584f002fd45f")
}

private fun run_klib_1eab86b635e53e32() {
    callbacks = 0
    println("BEGIN:klib-1eab86b635e53e32")
    try {
        val target: Sink = Buffer()
        val input0: UByte = 1.toUByte()
        try {
            f01_klib_1eab86b635e53e32(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-1eab86b635e53e32")
}

private fun run_klib_21b369685533b320() {
    callbacks = 0
    println("BEGIN:klib-21b369685533b320")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Long = 2L
        try {
            f01_klib_21b369685533b320(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-21b369685533b320")
}

private fun run_klib_21d678c0082fac12() {
    callbacks = 0
    println("BEGIN:klib-21d678c0082fac12")
    try {
        val target: Sink = Buffer()
        val input0: UInt = 1U
        try {
            f01_klib_21d678c0082fac12(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-21d678c0082fac12")
}

private fun run_klib_234dcde51a17e6be() {
    callbacks = 0
    println("BEGIN:klib-234dcde51a17e6be")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_234dcde51a17e6be(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-234dcde51a17e6be")
}

private fun run_klib_287cb83cbbb8abf0() {
    callbacks = 0
    println("BEGIN:klib-287cb83cbbb8abf0")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Buffer = seed()
        val input1: Long = 2L
        try {
            f01_klib_287cb83cbbb8abf0(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-287cb83cbbb8abf0")
}

private fun run_klib_28ad704738de4392() {
    callbacks = 0
    println("BEGIN:klib-28ad704738de4392")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Long = 0L
        try {
            f01_klib_28ad704738de4392(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-28ad704738de4392")
}

private fun run_klib_28f888234979270b() {
    callbacks = 0
    println("BEGIN:klib-28f888234979270b")
    try {
        val target: Sink = Buffer()
        val input0: UShort = 1.toUShort()
        try {
            f01_klib_28f888234979270b(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-28f888234979270b")
}

private fun run_klib_293d4e80c1fd216b() {
    callbacks = 0
    println("BEGIN:klib-293d4e80c1fd216b")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: Int = 0
        val input1: Int = 2
        try {
            f01_klib_293d4e80c1fd216b(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-293d4e80c1fd216b")
}

private fun run_klib_2a3c8fc10ad9fe98() {
    callbacks = 0
    println("BEGIN:klib-2a3c8fc10ad9fe98")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        val input1: Boolean = false
        try {
            f01_klib_2a3c8fc10ad9fe98(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-2a3c8fc10ad9fe98")
}

private fun run_klib_30f3a5c70398830b() {
    callbacks = 0
    println("BEGIN:klib-30f3a5c70398830b")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input2: Int = 0
        val input3: Int = 0
        val input4: Int = 2
        try {
            f01_klib_30f3a5c70398830b(input0, input1, input2, input3, input4)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
            println("state:input3:" + observe(input3))
            println("state:input4:" + observe(input4))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-30f3a5c70398830b")
}

private fun run_klib_326c123a5833a082() {
    callbacks = 0
    println("BEGIN:klib-326c123a5833a082")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        try {
            f01_klib_326c123a5833a082(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-326c123a5833a082")
}

private fun run_klib_3445037415447ceb() {
    callbacks = 0
    println("BEGIN:klib-3445037415447ceb")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_3445037415447ceb(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3445037415447ceb")
}

private fun run_klib_3458721120f74265() {
    callbacks = 0
    println("BEGIN:klib-3458721120f74265")
    try {
        val target: kotlinx.io.RawSink = Buffer()
        try {
            f01_klib_3458721120f74265(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3458721120f74265")
}

private fun run_klib_362345f57ba26256() {
    callbacks = 0
    println("BEGIN:klib-362345f57ba26256")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_362345f57ba26256(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-362345f57ba26256")
}

private fun run_klib_3849b34106c51c0d() {
    callbacks = 0
    println("BEGIN:klib-3849b34106c51c0d")
    try {
        val target: Source = seed()
        try {
            f01_klib_3849b34106c51c0d(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3849b34106c51c0d")
}

private fun run_klib_3892125bf6d12ddd() {
    callbacks = 0
    println("BEGIN:klib-3892125bf6d12ddd")
    try {
        val target: Source = seed()
        try {
            f01_klib_3892125bf6d12ddd(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3892125bf6d12ddd")
}

private fun run_klib_3a26229075e48265() {
    callbacks = 0
    println("BEGIN:klib-3a26229075e48265")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        try {
            f01_klib_3a26229075e48265(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3a26229075e48265")
}

private fun run_klib_3c68d271a161568d() {
    callbacks = 0
    println("BEGIN:klib-3c68d271a161568d")
    try {
        val target: Source = seed()
        val input0: Int = 2
        try {
            f01_klib_3c68d271a161568d(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3c68d271a161568d")
}

private fun run_klib_3c9070b2e4f85e53() {
    callbacks = 0
    println("BEGIN:klib-3c9070b2e4f85e53")
    try {
        val target: kotlinx.io.files.FileMetadata = FileMetadata(false, false, 0L)
        try {
            f01_klib_3c9070b2e4f85e53(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3c9070b2e4f85e53")
}

private fun run_klib_3d19f06be0624572() {
    callbacks = 0
    println("BEGIN:klib-3d19f06be0624572")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_3d19f06be0624572(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3d19f06be0624572")
}

private fun run_klib_3d41c73755becbfd() {
    callbacks = 0
    println("BEGIN:klib-3d41c73755becbfd")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: Short = 1.toShort()
        try {
            f01_klib_3d41c73755becbfd(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3d41c73755becbfd")
}

private fun run_klib_3d59e06c36c0de2c() {
    callbacks = 0
    println("BEGIN:klib-3d59e06c36c0de2c")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_3d59e06c36c0de2c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3d59e06c36c0de2c")
}

private fun run_klib_3f0132b282858278() {
    callbacks = 0
    println("BEGIN:klib-3f0132b282858278")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.iterate(contextBuffer) { context, segment ->
            val target: kotlinx.io.unsafe.BufferIterationContext = context
            try {
                f01_klib_3f0132b282858278(target)
            } finally {
                println("state:target:" + observe(target))
            }
        Unit
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3f0132b282858278")
}

private fun run_klib_3fa0f868cc4fbb72() {
    callbacks = 0
    println("BEGIN:klib-3fa0f868cc4fbb72")
    try {
        val target: kotlinx.io.Sink = Buffer()
        try {
            f01_klib_3fa0f868cc4fbb72(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-3fa0f868cc4fbb72")
}

private fun run_klib_401b5e99cf0a6795() {
    callbacks = 0
    println("BEGIN:klib-401b5e99cf0a6795")
    try {
        val input0: Byte = 1.toByte()
        try {
            f01_klib_401b5e99cf0a6795(input0)
        } finally {
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-401b5e99cf0a6795")
}

private fun run_klib_40e8547b6dd7ad90() {
    callbacks = 0
    println("BEGIN:klib-40e8547b6dd7ad90")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: Byte = 1.toByte()
        val input1: Int = 0
        try {
            f01_klib_40e8547b6dd7ad90(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-40e8547b6dd7ad90")
}

private fun run_klib_41e3c3eeaaba19c0() {
    callbacks = 0
    println("BEGIN:klib-41e3c3eeaaba19c0")
    try {
        val target: Sink = Buffer()
        val input0: (Buffer) -> Unit = { arg0 -> callbacks++; Unit }
        try {
            f01_klib_41e3c3eeaaba19c0(target, input0)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-41e3c3eeaaba19c0")
}

private fun run_klib_42970e7fff753d0c() {
    callbacks = 0
    println("BEGIN:klib-42970e7fff753d0c")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_42970e7fff753d0c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-42970e7fff753d0c")
}

private fun run_klib_4321c6311cdce9b7() {
    callbacks = 0
    println("BEGIN:klib-4321c6311cdce9b7")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_4321c6311cdce9b7(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4321c6311cdce9b7")
}

private fun run_klib_4366654b667dcd7f() {
    callbacks = 0
    println("BEGIN:klib-4366654b667dcd7f")
    try {
        val target: Buffer = seed()
        try {
            f01_klib_4366654b667dcd7f(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4366654b667dcd7f")
}

private fun run_klib_4709034f040eb8ff() {
    callbacks = 0
    println("BEGIN:klib-4709034f040eb8ff")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        try {
            f01_klib_4709034f040eb8ff(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4709034f040eb8ff")
}

private fun run_klib_47da668f67cb4abb() {
    callbacks = 0
    println("BEGIN:klib-47da668f67cb4abb")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        try {
            f01_klib_47da668f67cb4abb(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-47da668f67cb4abb")
}

private fun run_klib_49fed0452a7d05c0() {
    callbacks = 0
    println("BEGIN:klib-49fed0452a7d05c0")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Int = 0
        try {
            f01_klib_49fed0452a7d05c0(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-49fed0452a7d05c0")
}

private fun run_klib_4aa81c5400af93fe() {
    callbacks = 0
    println("BEGIN:klib-4aa81c5400af93fe")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: kotlinx.io.Segment = segment!!
            try {
                f01_klib_4aa81c5400af93fe(target)
            } finally {
                println("state:target:" + observe(target))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4aa81c5400af93fe")
}

private fun run_klib_4ab35f2484026657() {
    callbacks = 0
    println("BEGIN:klib-4ab35f2484026657")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: kotlinx.io.Segment = segment!!
            try {
                f01_klib_4ab35f2484026657(target)
            } finally {
                println("state:target:" + observe(target))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4ab35f2484026657")
}

private fun run_klib_4d280feb368bb149() {
    callbacks = 0
    println("BEGIN:klib-4d280feb368bb149")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: HexFormat = HexFormat.Default
        try {
            f01_klib_4d280feb368bb149(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4d280feb368bb149")
}

private fun run_klib_4d38fa01cf9280a5() {
    callbacks = 0
    println("BEGIN:klib-4d38fa01cf9280a5")
    try {
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_4d38fa01cf9280a5(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4d38fa01cf9280a5")
}

private fun run_klib_4dad9fe908d53ceb() {
    callbacks = 0
    println("BEGIN:klib-4dad9fe908d53ceb")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Long = 0L
        try {
            f01_klib_4dad9fe908d53ceb(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4dad9fe908d53ceb")
}

private fun run_klib_4ee0099543291bca() {
    callbacks = 0
    println("BEGIN:klib-4ee0099543291bca")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->
            context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())
            val target: kotlinx.io.unsafe.SegmentWriteContext = context
            try {
                f01_klib_4ee0099543291bca(target)
            } finally {
                println("state:target:" + observe(target))
            }
        4
    }
    println("committed:" + observe(contextBuffer))
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-4ee0099543291bca")
}

private fun run_klib_51d6c72a1f365869() {
    callbacks = 0
    println("BEGIN:klib-51d6c72a1f365869")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: Byte = 1.toByte()
        try {
            f01_klib_51d6c72a1f365869(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-51d6c72a1f365869")
}

private fun run_klib_531fa1db0425b6e0() {
    callbacks = 0
    println("BEGIN:klib-531fa1db0425b6e0")
    try {
        val target: String = "0102"
        val input0: HexFormat = HexFormat.Default
        try {
            f01_klib_531fa1db0425b6e0(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-531fa1db0425b6e0")
}

private fun run_klib_539fc5d95ef77842() {
    callbacks = 0
    println("BEGIN:klib-539fc5d95ef77842")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        try {
            f01_klib_539fc5d95ef77842(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-539fc5d95ef77842")
}

private fun run_klib_53ba821bab96c77e() {
    callbacks = 0
    println("BEGIN:klib-53ba821bab96c77e")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Long = 2L
        try {
            f01_klib_53ba821bab96c77e(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-53ba821bab96c77e")
}

private fun run_klib_54782273b181aa94() {
    callbacks = 0
    println("BEGIN:klib-54782273b181aa94")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: Int = 0
        val input1: Int = 2
        try {
            f01_klib_54782273b181aa94(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-54782273b181aa94")
}

private fun run_klib_55dcad01b8bc6432() {
    callbacks = 0
    println("BEGIN:klib-55dcad01b8bc6432")
    try {
        val target: kotlinx.io.RawSource = seed()
        try {
            f01_klib_55dcad01b8bc6432(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-55dcad01b8bc6432")
}

private fun run_klib_56c50bf69a16e323() {
    callbacks = 0
    println("BEGIN:klib-56c50bf69a16e323")
    try {
        val target: Source = seed()
        try {
            f01_klib_56c50bf69a16e323(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-56c50bf69a16e323")
}

private fun run_klib_58329ccccc665665() {
    callbacks = 0
    println("BEGIN:klib-58329ccccc665665")
    try {
        val target: Source = seed()
        try {
            f01_klib_58329ccccc665665(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-58329ccccc665665")
}

private fun run_klib_5864c1c328005421() {
    callbacks = 0
    println("BEGIN:klib-5864c1c328005421")
    try {
        val target: Source = seed()
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Long = 0L
        try {
            f01_klib_5864c1c328005421(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-5864c1c328005421")
}

private fun run_klib_588a0ffe0361140c() {
    callbacks = 0
    println("BEGIN:klib-588a0ffe0361140c")
    try {
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_588a0ffe0361140c(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-588a0ffe0361140c")
}

private fun run_klib_5930fa79e883d19e() {
    callbacks = 0
    println("BEGIN:klib-5930fa79e883d19e")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_5930fa79e883d19e(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-5930fa79e883d19e")
}

private fun run_klib_5b4b7a703c6dd6be() {
    callbacks = 0
    println("BEGIN:klib-5b4b7a703c6dd6be")
    try {
        val target: Source = seed()
        val input0: Long = 0L
        try {
            f01_klib_5b4b7a703c6dd6be(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-5b4b7a703c6dd6be")
}

private fun run_klib_5bdd91ace02d887d() {
    callbacks = 0
    println("BEGIN:klib-5bdd91ace02d887d")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        try {
            f01_klib_5bdd91ace02d887d(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-5bdd91ace02d887d")
}

private fun run_klib_5d6164d0dc5c0d36() {
    callbacks = 0
    println("BEGIN:klib-5d6164d0dc5c0d36")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_5d6164d0dc5c0d36(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-5d6164d0dc5c0d36")
}

private fun run_klib_61d456e1445185b3() {
    callbacks = 0
    println("BEGIN:klib-61d456e1445185b3")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input2: Int = 0
        val input3: Int = 0
        val input4: Int = 2
        try {
            f01_klib_61d456e1445185b3(input0, input1, input2, input3, input4)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
            println("state:input3:" + observe(input3))
            println("state:input4:" + observe(input4))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-61d456e1445185b3")
}

private fun run_klib_63d334f6656afcd4() {
    callbacks = 0
    println("BEGIN:klib-63d334f6656afcd4")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_63d334f6656afcd4(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-63d334f6656afcd4")
}

private fun run_klib_65e6983c396014fe() {
    callbacks = 0
    println("BEGIN:klib-65e6983c396014fe")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Long = 2L
        try {
            f01_klib_65e6983c396014fe(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-65e6983c396014fe")
}

private fun run_klib_67716886daea09d4() {
    callbacks = 0
    println("BEGIN:klib-67716886daea09d4")
    try {
        val input0: Path = Path("f02-path")
        val input1: String = "0102"
        try {
            f01_klib_67716886daea09d4(input0, input1)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-67716886daea09d4")
}

private fun run_klib_682923f3d5dba325() {
    callbacks = 0
    println("BEGIN:klib-682923f3d5dba325")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_682923f3d5dba325(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-682923f3d5dba325")
}

private fun run_klib_68baf701ff31ad9b() {
    callbacks = 0
    println("BEGIN:klib-68baf701ff31ad9b")
    try {
        val target: Source = seed()
        try {
            f01_klib_68baf701ff31ad9b(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-68baf701ff31ad9b")
}

private fun run_klib_6ac82acec38abefe() {
    callbacks = 0
    println("BEGIN:klib-6ac82acec38abefe")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_6ac82acec38abefe(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6ac82acec38abefe")
}

private fun run_klib_6acf344318aaed3d() {
    callbacks = 0
    println("BEGIN:klib-6acf344318aaed3d")
    try {
        val target: Sink = Buffer()
        val input0: ULong = 1UL
        try {
            f01_klib_6acf344318aaed3d(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6acf344318aaed3d")
}

private fun run_klib_6b0debf09de64260() {
    callbacks = 0
    println("BEGIN:klib-6b0debf09de64260")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_6b0debf09de64260(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6b0debf09de64260")
}

private fun run_klib_6b354812fb812d2e() {
    callbacks = 0
    println("BEGIN:klib-6b354812fb812d2e")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_6b354812fb812d2e(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6b354812fb812d2e")
}

private fun run_klib_6c944335ca7a6f05() {
    callbacks = 0
    println("BEGIN:klib-6c944335ca7a6f05")
    try {
        val target: Source = seed()
        try {
            f01_klib_6c944335ca7a6f05(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6c944335ca7a6f05")
}

private fun run_klib_6d6284225d20375c() {
    callbacks = 0
    println("BEGIN:klib-6d6284225d20375c")
    try {
        val target: Sink = Buffer()
        val input0: UShort = 1.toUShort()
        try {
            f01_klib_6d6284225d20375c(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6d6284225d20375c")
}

private fun run_klib_6dedd324c4f63d01() {
    callbacks = 0
    println("BEGIN:klib-6dedd324c4f63d01")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.iterate(contextBuffer) { context, segment ->
            val target: kotlinx.io.unsafe.BufferIterationContext = context
            val input0: Segment = segment!!
            try {
                f01_klib_6dedd324c4f63d01(target, input0)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
            }
        Unit
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6dedd324c4f63d01")
}

private fun run_klib_6ec3d2252d99b756() {
    callbacks = 0
    println("BEGIN:klib-6ec3d2252d99b756")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_6ec3d2252d99b756(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6ec3d2252d99b756")
}

private fun run_klib_6f8d15cfbf83da14() {
    callbacks = 0
    println("BEGIN:klib-6f8d15cfbf83da14")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: Byte = 1.toByte()
        val input1: Int = 0
        try {
            f01_klib_6f8d15cfbf83da14(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6f8d15cfbf83da14")
}

private fun run_klib_6ffc7a3dfb94a6d5() {
    callbacks = 0
    println("BEGIN:klib-6ffc7a3dfb94a6d5")
    try {
        val target: Source = seed()
        try {
            f01_klib_6ffc7a3dfb94a6d5(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-6ffc7a3dfb94a6d5")
}

private fun run_klib_71da4182a46d1646() {
    callbacks = 0
    println("BEGIN:klib-71da4182a46d1646")
    try {
        val target: Sink = Buffer()
        val input0: Long = 0L
        try {
            f01_klib_71da4182a46d1646(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-71da4182a46d1646")
}

private fun run_klib_71f9420a3c56c708() {
    callbacks = 0
    println("BEGIN:klib-71f9420a3c56c708")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_71f9420a3c56c708(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-71f9420a3c56c708")
}

private fun run_klib_729acf48b031cbef() {
    callbacks = 0
    println("BEGIN:klib-729acf48b031cbef")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: RawSink = Buffer()
        val input1: Long = 2L
        try {
            f01_klib_729acf48b031cbef(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-729acf48b031cbef")
}

private fun run_klib_745d0e6a927e88a7() {
    callbacks = 0
    println("BEGIN:klib-745d0e6a927e88a7")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: RawSource = seed()
        val input1: Long = 2L
        try {
            f01_klib_745d0e6a927e88a7(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-745d0e6a927e88a7")
}

private fun run_klib_771b35c257c8cf6a() {
    callbacks = 0
    println("BEGIN:klib-771b35c257c8cf6a")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: Int = 0
        try {
            f01_klib_771b35c257c8cf6a(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-771b35c257c8cf6a")
}

private fun run_klib_77f7b41ec87f091b() {
    callbacks = 0
    println("BEGIN:klib-77f7b41ec87f091b")
    try {
        val target: Sink = Buffer()
        val input0: Double = 1.25
        try {
            f01_klib_77f7b41ec87f091b(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-77f7b41ec87f091b")
}

private fun run_klib_784aceb83262b495() {
    callbacks = 0
    println("BEGIN:klib-784aceb83262b495")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_784aceb83262b495(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-784aceb83262b495")
}

private fun run_klib_78eaf273a0fd2845() {
    callbacks = 0
    println("BEGIN:klib-78eaf273a0fd2845")
    try {
        val target: Source = seed()
        val input0: Byte = 1.toByte()
        try {
            f01_klib_78eaf273a0fd2845(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-78eaf273a0fd2845")
}

private fun run_klib_7924258da3f788aa() {
    callbacks = 0
    println("BEGIN:klib-7924258da3f788aa")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        try {
            f01_klib_7924258da3f788aa(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7924258da3f788aa")
}

private fun run_klib_795e5c923ef63bf3() {
    callbacks = 0
    println("BEGIN:klib-795e5c923ef63bf3")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_795e5c923ef63bf3(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-795e5c923ef63bf3")
}

private fun run_klib_7b507920fd698e70() {
    callbacks = 0
    println("BEGIN:klib-7b507920fd698e70")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int = { arg0, arg1, arg2 -> callbacks++; 0 }
        try {
            f01_klib_7b507920fd698e70(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7b507920fd698e70")
}

private fun run_klib_7be24b4f67123949() {
    callbacks = 0
    println("BEGIN:klib-7be24b4f67123949")
    try {
        val target: ByteStringBuilder = ByteStringBuilder()
        val input0: UByte = 1.toUByte()
        try {
            f01_klib_7be24b4f67123949(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7be24b4f67123949")
}

private fun run_klib_7c6ab4850e567de3() {
    callbacks = 0
    println("BEGIN:klib-7c6ab4850e567de3")
    try {
        val target: kotlinx.io.Sink = Buffer()
        try {
            f01_klib_7c6ab4850e567de3(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7c6ab4850e567de3")
}

private fun run_klib_7dc026044b757651() {
    callbacks = 0
    println("BEGIN:klib-7dc026044b757651")
    try {
        val target: ByteStringBuilder = ByteStringBuilder()
        val input0: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_7dc026044b757651(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7dc026044b757651")
}

private fun run_klib_7f75d8253eaeafaf() {
    callbacks = 0
    println("BEGIN:klib-7f75d8253eaeafaf")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: Long = 0L
        try {
            f01_klib_7f75d8253eaeafaf(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7f75d8253eaeafaf")
}

private fun run_klib_7fa788e47483b1b4() {
    callbacks = 0
    println("BEGIN:klib-7fa788e47483b1b4")
    try {
        val target: kotlinx.io.Sink = Buffer()
        try {
            f01_klib_7fa788e47483b1b4(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-7fa788e47483b1b4")
}

private fun run_klib_8069f1495ab8ee86() {
    callbacks = 0
    println("BEGIN:klib-8069f1495ab8ee86")
    try {
        val input0: String = "0102"
        try {
            f01_klib_8069f1495ab8ee86(input0)
        } finally {
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8069f1495ab8ee86")
}

private fun run_klib_81c0f707fbf38fac() {
    callbacks = 0
    println("BEGIN:klib-81c0f707fbf38fac")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_81c0f707fbf38fac(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-81c0f707fbf38fac")
}

private fun run_klib_82806ba38fe9b8f8() {
    callbacks = 0
    println("BEGIN:klib-82806ba38fe9b8f8")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: Int = 0
        val input1: Int = 2
        val input2: HexFormat = HexFormat.Default
        try {
            f01_klib_82806ba38fe9b8f8(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-82806ba38fe9b8f8")
}

private fun run_klib_82fdcdfcc61c4db5() {
    callbacks = 0
    println("BEGIN:klib-82fdcdfcc61c4db5")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: Long = 2L
        try {
            f01_klib_82fdcdfcc61c4db5(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-82fdcdfcc61c4db5")
}

private fun run_klib_836f7033c3a627e8() {
    callbacks = 0
    println("BEGIN:klib-836f7033c3a627e8")
    try {
        val target: Sink = Buffer()
        val input0: Int = 0
        try {
            f01_klib_836f7033c3a627e8(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-836f7033c3a627e8")
}

private fun run_klib_8408acee5eedc7d9() {
    callbacks = 0
    println("BEGIN:klib-8408acee5eedc7d9")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: kotlinx.io.unsafe.SegmentReadContext = context
            val input0: Segment = segment!!
            val input1: Int = 0
            try {
                f01_klib_8408acee5eedc7d9(target, input0, input1)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
                println("state:input1:" + observe(input1))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8408acee5eedc7d9")
}

private fun run_klib_8493cb924a1ec5ce() {
    callbacks = 0
    println("BEGIN:klib-8493cb924a1ec5ce")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: RawSink = Buffer()
        val input1: Long = 2L
        try {
            f01_klib_8493cb924a1ec5ce(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8493cb924a1ec5ce")
}

private fun run_klib_84c73602fe199d0b() {
    callbacks = 0
    println("BEGIN:klib-84c73602fe199d0b")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: Long = 2L
        try {
            f01_klib_84c73602fe199d0b(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-84c73602fe199d0b")
}

private fun run_klib_85d81d97b55e0af8() {
    callbacks = 0
    println("BEGIN:klib-85d81d97b55e0af8")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        try {
            f01_klib_85d81d97b55e0af8(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-85d81d97b55e0af8")
}

private fun run_klib_878bd78d78a70078() {
    callbacks = 0
    println("BEGIN:klib-878bd78d78a70078")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        try {
            f01_klib_878bd78d78a70078(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-878bd78d78a70078")
}

private fun run_klib_8882e2c069f67a5b() {
    callbacks = 0
    println("BEGIN:klib-8882e2c069f67a5b")
    try {
        val target: RawSink = Buffer()
        try {
            f01_klib_8882e2c069f67a5b(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8882e2c069f67a5b")
}

private fun run_klib_88bbb664f38f686c() {
    callbacks = 0
    println("BEGIN:klib-88bbb664f38f686c")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_88bbb664f38f686c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-88bbb664f38f686c")
}

private fun run_klib_8a4d65b40a0bf57d() {
    callbacks = 0
    println("BEGIN:klib-8a4d65b40a0bf57d")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_8a4d65b40a0bf57d(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8a4d65b40a0bf57d")
}

private fun run_klib_8ad508ac6d89d176() {
    callbacks = 0
    println("BEGIN:klib-8ad508ac6d89d176")
    try {
        val input0: Boolean = false
        val input1: Boolean = false
        val input2: Long = 0L
        try {
            f01_klib_8ad508ac6d89d176(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8ad508ac6d89d176")
}

private fun run_klib_8b2ad25426b57149() {
    callbacks = 0
    println("BEGIN:klib-8b2ad25426b57149")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        val input0: Any? = null
        try {
            f01_klib_8b2ad25426b57149(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8b2ad25426b57149")
}

private fun run_klib_8b5e3dc06b358522() {
    callbacks = 0
    println("BEGIN:klib-8b5e3dc06b358522")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        try {
            f01_klib_8b5e3dc06b358522(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8b5e3dc06b358522")
}

private fun run_klib_8bffc09edd89a6f5() {
    callbacks = 0
    println("BEGIN:klib-8bffc09edd89a6f5")
    try {
        val target: Source = seed()
        try {
            f01_klib_8bffc09edd89a6f5(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8bffc09edd89a6f5")
}

private fun run_klib_8cb9bc77e047d21d() {
    callbacks = 0
    println("BEGIN:klib-8cb9bc77e047d21d")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: RawSink = Buffer()
        try {
            f01_klib_8cb9bc77e047d21d(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8cb9bc77e047d21d")
}

private fun run_klib_8eb9402560ac1395() {
    callbacks = 0
    println("BEGIN:klib-8eb9402560ac1395")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_8eb9402560ac1395(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8eb9402560ac1395")
}

private fun run_klib_8f2cd67956fefb8b() {
    callbacks = 0
    println("BEGIN:klib-8f2cd67956fefb8b")
    try {
        val target: Buffer = seed()
        val input0: Byte = 1.toByte()
        val input1: Long = 0L
        val input2: Long = 2L
        try {
            f01_klib_8f2cd67956fefb8b(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-8f2cd67956fefb8b")
}

private fun run_klib_95ecf7a5c44877fd() {
    callbacks = 0
    println("BEGIN:klib-95ecf7a5c44877fd")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        try {
            f01_klib_95ecf7a5c44877fd(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-95ecf7a5c44877fd")
}

private fun run_klib_97b03a52b446f7a8() {
    callbacks = 0
    println("BEGIN:klib-97b03a52b446f7a8")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        val input0: Any? = null
        try {
            f01_klib_97b03a52b446f7a8(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-97b03a52b446f7a8")
}

private fun run_klib_99561fb55e3c6768() {
    callbacks = 0
    println("BEGIN:klib-99561fb55e3c6768")
    try {
        val target: Sink = Buffer()
        val input0: Short = 1.toShort()
        try {
            f01_klib_99561fb55e3c6768(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-99561fb55e3c6768")
}

private fun run_klib_998e3a41ef776da3() {
    callbacks = 0
    println("BEGIN:klib-998e3a41ef776da3")
    try {
        val target: kotlinx.io.files.FileMetadata = FileMetadata(false, false, 0L)
        try {
            f01_klib_998e3a41ef776da3(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-998e3a41ef776da3")
}

private fun run_klib_9c9c8d555bae0054() {
    callbacks = 0
    println("BEGIN:klib-9c9c8d555bae0054")
    try {
        val target: kotlinx.io.files.FileMetadata = FileMetadata(false, false, 0L)
        try {
            f01_klib_9c9c8d555bae0054(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-9c9c8d555bae0054")
}

private fun run_klib_9d0cebae9efff846() {
    callbacks = 0
    println("BEGIN:klib-9d0cebae9efff846")
    try {
        val target: kotlinx.io.RawSink = Buffer()
        try {
            f01_klib_9d0cebae9efff846(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-9d0cebae9efff846")
}

private fun run_klib_9d2139e2b8e2d1da() {
    callbacks = 0
    println("BEGIN:klib-9d2139e2b8e2d1da")
    try {
        val input0: String = "0102"
        val input1: String = "0102"
        try {
            f01_klib_9d2139e2b8e2d1da(input0, input1)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-9d2139e2b8e2d1da")
}

private fun run_klib_9f044f29c7d0c7f7() {
    callbacks = 0
    println("BEGIN:klib-9f044f29c7d0c7f7")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: (context: SegmentReadContext, segment: Segment) -> Unit = { arg0, arg1 -> callbacks++; Unit }
        try {
            f01_klib_9f044f29c7d0c7f7(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-9f044f29c7d0c7f7")
}

private fun run_klib_a00bfbcc6ee356ae() {
    callbacks = 0
    println("BEGIN:klib-a00bfbcc6ee356ae")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: Int = 1
        val input2: (context: SegmentWriteContext, tail: Segment) -> Int = { arg0, arg1 -> callbacks++; 0 }
        try {
            f01_klib_a00bfbcc6ee356ae(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a00bfbcc6ee356ae")
}

private fun run_klib_a0fc40513a876e95() {
    callbacks = 0
    println("BEGIN:klib-a0fc40513a876e95")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_a0fc40513a876e95(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a0fc40513a876e95")
}

private fun run_klib_a547abadbdde0d10() {
    callbacks = 0
    println("BEGIN:klib-a547abadbdde0d10")
    try {
        val target: kotlinx.io.files.FileMetadata = FileMetadata(false, false, 0L)
        try {
            f01_klib_a547abadbdde0d10(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a547abadbdde0d10")
}

private fun run_klib_a6ee175ecb9390e8() {
    callbacks = 0
    println("BEGIN:klib-a6ee175ecb9390e8")
    try {
        val target: Source = seed()
        try {
            f01_klib_a6ee175ecb9390e8(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a6ee175ecb9390e8")
}

private fun run_klib_a97fa5c19fd45e36() {
    callbacks = 0
    println("BEGIN:klib-a97fa5c19fd45e36")
    try {
        val target: Source = seed()
        try {
            f01_klib_a97fa5c19fd45e36(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a97fa5c19fd45e36")
}

private fun run_klib_a9d4f29aa2f8d0a7() {
    callbacks = 0
    println("BEGIN:klib-a9d4f29aa2f8d0a7")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        try {
            f01_klib_a9d4f29aa2f8d0a7(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-a9d4f29aa2f8d0a7")
}

private fun run_klib_aada9b079769b5b8() {
    callbacks = 0
    println("BEGIN:klib-aada9b079769b5b8")
    try {
        val input0: CharSequence = "0102"
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_aada9b079769b5b8(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-aada9b079769b5b8")
}

private fun run_klib_ac359cf3beddc6af() {
    callbacks = 0
    println("BEGIN:klib-ac359cf3beddc6af")
    try {
        val target: Source = seed()
        try {
            f01_klib_ac359cf3beddc6af(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ac359cf3beddc6af")
}

private fun run_klib_ad970e42737004ba() {
    callbacks = 0
    println("BEGIN:klib-ad970e42737004ba")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Buffer = seed()
        val input1: Long = 0L
        val input2: Long = 2L
        try {
            f01_klib_ad970e42737004ba(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ad970e42737004ba")
}

private fun run_klib_ae2e25bc70cb0f81() {
    callbacks = 0
    println("BEGIN:klib-ae2e25bc70cb0f81")
    try {
        val target: Sink = Buffer()
        val input0: Double = 1.25
        try {
            f01_klib_ae2e25bc70cb0f81(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ae2e25bc70cb0f81")
}

private fun run_klib_ae9bd202449ab479() {
    callbacks = 0
    println("BEGIN:klib-ae9bd202449ab479")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_ae9bd202449ab479(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ae9bd202449ab479")
}

private fun run_klib_af3495d0cd999087() {
    callbacks = 0
    println("BEGIN:klib-af3495d0cd999087")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_af3495d0cd999087(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-af3495d0cd999087")
}

private fun run_klib_b0cbc86985848be3() {
    callbacks = 0
    println("BEGIN:klib-b0cbc86985848be3")
    try {
        val target: Source = seed()
        val input0: Int = 2
        try {
            f01_klib_b0cbc86985848be3(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b0cbc86985848be3")
}

private fun run_klib_b2e78491a07af06a() {
    callbacks = 0
    println("BEGIN:klib-b2e78491a07af06a")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: Int = 1
        val input2: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int = { arg0, arg1, arg2 -> callbacks++; 0 }
        try {
            f01_klib_b2e78491a07af06a(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b2e78491a07af06a")
}

private fun run_klib_b33ce5b385a93879() {
    callbacks = 0
    println("BEGIN:klib-b33ce5b385a93879")
    try {
        val target: Buffer = seed()
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Long = 0L
        try {
            f01_klib_b33ce5b385a93879(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b33ce5b385a93879")
}

private fun run_klib_b375c9addf24d27c() {
    callbacks = 0
    println("BEGIN:klib-b375c9addf24d27c")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_b375c9addf24d27c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b375c9addf24d27c")
}

private fun run_klib_b3c4163f48365984() {
    callbacks = 0
    println("BEGIN:klib-b3c4163f48365984")
    try {
        try {
            f01_klib_b3c4163f48365984()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b3c4163f48365984")
}

private fun run_klib_b3facb03c7099028() {
    callbacks = 0
    println("BEGIN:klib-b3facb03c7099028")
    try {
        val target: kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations = UnsafeByteStringOperations
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: (ByteArray) -> Unit = { arg0 -> callbacks++; Unit }
        try {
            f01_klib_b3facb03c7099028(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b3facb03c7099028")
}

private fun run_klib_b4c0c7877dbf9c38() {
    callbacks = 0
    println("BEGIN:klib-b4c0c7877dbf9c38")
    try {
        val target: Source = seed()
        try {
            f01_klib_b4c0c7877dbf9c38(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b4c0c7877dbf9c38")
}

private fun run_klib_b6239168ccc071cf() {
    callbacks = 0
    println("BEGIN:klib-b6239168ccc071cf")
    try {
        val target: Sink = Buffer()
        val input0: Float = 1.25f
        try {
            f01_klib_b6239168ccc071cf(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b6239168ccc071cf")
}

private fun run_klib_b7a1e3746605766a() {
    callbacks = 0
    println("BEGIN:klib-b7a1e3746605766a")
    try {
        val target: Sink = Buffer()
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_b7a1e3746605766a(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b7a1e3746605766a")
}

private fun run_klib_b8615ffaceb2162f() {
    callbacks = 0
    println("BEGIN:klib-b8615ffaceb2162f")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->
            context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())
            val target: kotlinx.io.unsafe.SegmentWriteContext = context
            val input0: Segment = segment!!
            val input1: Int = 0
            val input2: Byte = 1.toByte()
            try {
                f01_klib_b8615ffaceb2162f(target, input0, input1, input2)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
                println("state:input1:" + observe(input1))
                println("state:input2:" + observe(input2))
            }
        4
    }
    println("committed:" + observe(contextBuffer))
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b8615ffaceb2162f")
}

private fun run_klib_b8c0f5c01e53eba4() {
    callbacks = 0
    println("BEGIN:klib-b8c0f5c01e53eba4")
    try {
        val target: ByteStringBuilder = ByteStringBuilder()
        val input0: Byte = 1.toByte()
        try {
            f01_klib_b8c0f5c01e53eba4(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b8c0f5c01e53eba4")
}

private fun run_klib_b8c4ea47b33d74eb() {
    callbacks = 0
    println("BEGIN:klib-b8c4ea47b33d74eb")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input1: Int = 0
        try {
            f01_klib_b8c4ea47b33d74eb(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b8c4ea47b33d74eb")
}

private fun run_klib_b8cef78e807482ab() {
    callbacks = 0
    println("BEGIN:klib-b8cef78e807482ab")
    try {
        val target: Source = seed()
        try {
            f01_klib_b8cef78e807482ab(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b8cef78e807482ab")
}

private fun run_klib_b8d3dfb575d2ea24() {
    callbacks = 0
    println("BEGIN:klib-b8d3dfb575d2ea24")
    try {
        val target: kotlinx.io.RawSink = Buffer()
        try {
            f01_klib_b8d3dfb575d2ea24(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b8d3dfb575d2ea24")
}

private fun run_klib_b99e5e474e73e737() {
    callbacks = 0
    println("BEGIN:klib-b99e5e474e73e737")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        try {
            f01_klib_b99e5e474e73e737(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-b99e5e474e73e737")
}

private fun run_klib_ba8f18b87d64cda0() {
    callbacks = 0
    println("BEGIN:klib-ba8f18b87d64cda0")
    try {
        val target: kotlinx.io.files.Path = Path("f02-path")
        try {
            f01_klib_ba8f18b87d64cda0(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ba8f18b87d64cda0")
}

private fun run_klib_bb1a86c235fe5d90() {
    callbacks = 0
    println("BEGIN:klib-bb1a86c235fe5d90")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        try {
            f01_klib_bb1a86c235fe5d90(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-bb1a86c235fe5d90")
}

private fun run_klib_bb9ffc979ba60de7() {
    callbacks = 0
    println("BEGIN:klib-bb9ffc979ba60de7")
    try {
        val target: Source = seed()
        try {
            f01_klib_bb9ffc979ba60de7(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-bb9ffc979ba60de7")
}

private fun run_klib_bdf28cb8bae382ca() {
    callbacks = 0
    println("BEGIN:klib-bdf28cb8bae382ca")
    try {
        val target: kotlinx.io.RawSource = seed()
        try {
            f01_klib_bdf28cb8bae382ca(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-bdf28cb8bae382ca")
}

private fun run_klib_be8b25c44d1b4769() {
    callbacks = 0
    println("BEGIN:klib-be8b25c44d1b4769")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_be8b25c44d1b4769(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-be8b25c44d1b4769")
}

private fun run_klib_c0f160e916c84945() {
    callbacks = 0
    println("BEGIN:klib-c0f160e916c84945")
    try {
        try {
            f01_klib_c0f160e916c84945()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c0f160e916c84945")
}

private fun run_klib_c16a9382b66a0d92() {
    callbacks = 0
    println("BEGIN:klib-c16a9382b66a0d92")
    try {
        try {
            f01_klib_c16a9382b66a0d92()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c16a9382b66a0d92")
}

private fun run_klib_c2b35bc7da1ac135() {
    callbacks = 0
    println("BEGIN:klib-c2b35bc7da1ac135")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_c2b35bc7da1ac135(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c2b35bc7da1ac135")
}

private fun run_klib_c43c18bee4ac34f0() {
    callbacks = 0
    println("BEGIN:klib-c43c18bee4ac34f0")
    try {
        val input0: Int = 0
        try {
            f01_klib_c43c18bee4ac34f0(input0)
        } finally {
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c43c18bee4ac34f0")
}

private fun run_klib_c5967cbbd4139ae7() {
    callbacks = 0
    println("BEGIN:klib-c5967cbbd4139ae7")
    try {
        val target: kotlinx.io.Source = seed()
        val input0: Long = 2L
        try {
            f01_klib_c5967cbbd4139ae7(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c5967cbbd4139ae7")
}

private fun run_klib_c69fb04271e9017f() {
    callbacks = 0
    println("BEGIN:klib-c69fb04271e9017f")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_c69fb04271e9017f(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c69fb04271e9017f")
}

private fun run_klib_c7f1b2f55bd05ce9() {
    callbacks = 0
    println("BEGIN:klib-c7f1b2f55bd05ce9")
    try {
        val target: String = "0102"
        try {
            f01_klib_c7f1b2f55bd05ce9(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c7f1b2f55bd05ce9")
}

private fun run_klib_c859368e54032355() {
    callbacks = 0
    println("BEGIN:klib-c859368e54032355")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_c859368e54032355(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-c859368e54032355")
}

private fun run_klib_caa6adf5c94ccba4() {
    callbacks = 0
    println("BEGIN:klib-caa6adf5c94ccba4")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: Long = 0L
        val input2: (context: BufferIterationContext, segment: Segment?, startOfTheSegmentOffset: Long) -> Unit = { arg0, arg1, arg2 -> callbacks++; Unit }
        try {
            f01_klib_caa6adf5c94ccba4(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-caa6adf5c94ccba4")
}

private fun run_klib_cc0b8375fc87baf1() {
    callbacks = 0
    println("BEGIN:klib-cc0b8375fc87baf1")
    try {
        val target: Sink = Buffer()
        val input0: Int = 0
        try {
            f01_klib_cc0b8375fc87baf1(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-cc0b8375fc87baf1")
}

private fun run_klib_cd211a43d894fda6() {
    callbacks = 0
    println("BEGIN:klib-cd211a43d894fda6")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_cd211a43d894fda6(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-cd211a43d894fda6")
}

private fun run_klib_ce7c92aa2bfb72dc() {
    callbacks = 0
    println("BEGIN:klib-ce7c92aa2bfb72dc")
    try {
        try {
            f01_klib_ce7c92aa2bfb72dc()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ce7c92aa2bfb72dc")
}

private fun run_klib_cedf0ff273d5d352() {
    callbacks = 0
    println("BEGIN:klib-cedf0ff273d5d352")
    try {
        val target: kotlinx.io.unsafe.UnsafeBufferOperations = UnsafeBufferOperations
        val input0: Buffer = seed()
        val input1: ByteArray = byteArrayOf(1, 2, 3, 4)
        val input2: Int = 0
        val input3: Int = 2
        try {
            f01_klib_cedf0ff273d5d352(target, input0, input1, input2, input3)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
            println("state:input3:" + observe(input3))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-cedf0ff273d5d352")
}

private fun run_klib_d02d17dc3ff2b0ff() {
    callbacks = 0
    println("BEGIN:klib-d02d17dc3ff2b0ff")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_d02d17dc3ff2b0ff(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-d02d17dc3ff2b0ff")
}

private fun run_klib_d1cb273bd1667eae() {
    callbacks = 0
    println("BEGIN:klib-d1cb273bd1667eae")
    try {
        val input0: UByte = 1.toUByte()
        try {
            f01_klib_d1cb273bd1667eae(input0)
        } finally {
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-d1cb273bd1667eae")
}

private fun run_klib_d277df79b7105ad5() {
    callbacks = 0
    println("BEGIN:klib-d277df79b7105ad5")
    try {
        val input0: Int = 0
        val input1: ByteStringBuilder.() -> Unit = { callbacks++; append(7.toByte()) }
        try {
            f01_klib_d277df79b7105ad5(input0, input1)
        } finally {
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-d277df79b7105ad5")
}

private fun run_klib_d2f38ed9026aca01() {
    callbacks = 0
    println("BEGIN:klib-d2f38ed9026aca01")
    try {
        val target: Sink = Buffer()
        val input0: CharSequence = "0102"
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_d2f38ed9026aca01(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-d2f38ed9026aca01")
}

private fun run_klib_d622a899b3e52773() {
    callbacks = 0
    println("BEGIN:klib-d622a899b3e52773")
    try {
        val target: Sink = Buffer()
        val input0: UInt = 1U
        try {
            f01_klib_d622a899b3e52773(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-d622a899b3e52773")
}

private fun run_klib_da327fd9f523ef4d() {
    callbacks = 0
    println("BEGIN:klib-da327fd9f523ef4d")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_da327fd9f523ef4d(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-da327fd9f523ef4d")
}

private fun run_klib_db19efa34d4c840f() {
    callbacks = 0
    println("BEGIN:klib-db19efa34d4c840f")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Short = 1.toShort()
        try {
            f01_klib_db19efa34d4c840f(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-db19efa34d4c840f")
}

private fun run_klib_db1be29554216403() {
    callbacks = 0
    println("BEGIN:klib-db1be29554216403")
    try {
        val target: Sink = Buffer()
        val input0: Long = 0L
        try {
            f01_klib_db1be29554216403(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-db1be29554216403")
}

private fun run_klib_dc06afd6e7388ef3() {
    callbacks = 0
    println("BEGIN:klib-dc06afd6e7388ef3")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        try {
            f01_klib_dc06afd6e7388ef3(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-dc06afd6e7388ef3")
}

private fun run_klib_defd9573ba737c05() {
    callbacks = 0
    println("BEGIN:klib-defd9573ba737c05")
    try {
        val target: Source = seed()
        try {
            f01_klib_defd9573ba737c05(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-defd9573ba737c05")
}

private fun run_klib_dfc8f292cc42fe63() {
    callbacks = 0
    println("BEGIN:klib-dfc8f292cc42fe63")
    try {
        val target: Sink = Buffer()
        val input0: Long = 0L
        try {
            f01_klib_dfc8f292cc42fe63(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-dfc8f292cc42fe63")
}

private fun run_klib_e1f76e75c682b718() {
    callbacks = 0
    println("BEGIN:klib-e1f76e75c682b718")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_e1f76e75c682b718(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-e1f76e75c682b718")
}

private fun run_klib_e6692e8ba9801df3() {
    callbacks = 0
    println("BEGIN:klib-e6692e8ba9801df3")
    try {
        val target: RawSource = seed()
        try {
            f01_klib_e6692e8ba9801df3(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-e6692e8ba9801df3")
}

private fun run_klib_e73c2ae9564dc892() {
    callbacks = 0
    println("BEGIN:klib-e73c2ae9564dc892")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: RawSink = Buffer()
        try {
            f01_klib_e73c2ae9564dc892(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-e73c2ae9564dc892")
}

private fun run_klib_e872d95c8706832c() {
    callbacks = 0
    println("BEGIN:klib-e872d95c8706832c")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_e872d95c8706832c(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-e872d95c8706832c")
}

private fun run_klib_e8a815654759b526() {
    callbacks = 0
    println("BEGIN:klib-e8a815654759b526")
    try {
        val target: kotlinx.io.bytestring.ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_e8a815654759b526(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-e8a815654759b526")
}

private fun run_klib_ea2a6bf9a5d93882() {
    callbacks = 0
    println("BEGIN:klib-ea2a6bf9a5d93882")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: RawSource = seed()
        try {
            f01_klib_ea2a6bf9a5d93882(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ea2a6bf9a5d93882")
}

private fun run_klib_ea45816decad6959() {
    callbacks = 0
    println("BEGIN:klib-ea45816decad6959")
    try {
        val target: Sink = Buffer()
        val input0: String = "0102"
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_ea45816decad6959(target, input0, input1, input2)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ea45816decad6959")
}

private fun run_klib_eb2e0cdf209de26a() {
    callbacks = 0
    println("BEGIN:klib-eb2e0cdf209de26a")
    try {
        try {
            f01_klib_eb2e0cdf209de26a()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-eb2e0cdf209de26a")
}

private fun run_klib_ec5be87f1757e6b8() {
    callbacks = 0
    println("BEGIN:klib-ec5be87f1757e6b8")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_ec5be87f1757e6b8(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ec5be87f1757e6b8")
}

private fun run_klib_ee51a94316134963() {
    callbacks = 0
    println("BEGIN:klib-ee51a94316134963")
    try {
        try {
            f01_klib_ee51a94316134963()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ee51a94316134963")
}

private fun run_klib_ee5d9a571cd8e453() {
    callbacks = 0
    println("BEGIN:klib-ee5d9a571cd8e453")
    try {
        val target: kotlinx.io.bytestring.ByteStringBuilder = ByteStringBuilder()
        val input0: Byte = 1.toByte()
        try {
            f01_klib_ee5d9a571cd8e453(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ee5d9a571cd8e453")
}

private fun run_klib_f10f01d0ac1d5ee1() {
    callbacks = 0
    println("BEGIN:klib-f10f01d0ac1d5ee1")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Buffer = seed()
        val input1: Long = 2L
        try {
            f01_klib_f10f01d0ac1d5ee1(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f10f01d0ac1d5ee1")
}

private fun run_klib_f22691bc91e16f23() {
    callbacks = 0
    println("BEGIN:klib-f22691bc91e16f23")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_f22691bc91e16f23(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f22691bc91e16f23")
}

private fun run_klib_f24361849bd7cfdd() {
    callbacks = 0
    println("BEGIN:klib-f24361849bd7cfdd")
    try {
        try {
            f01_klib_f24361849bd7cfdd()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f24361849bd7cfdd")
}

private fun run_klib_f2a10f7f196b05da() {
    callbacks = 0
    println("BEGIN:klib-f2a10f7f196b05da")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: Byte = 1.toByte()
        try {
            f01_klib_f2a10f7f196b05da(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f2a10f7f196b05da")
}

private fun run_klib_f570c311693d6703() {
    callbacks = 0
    println("BEGIN:klib-f570c311693d6703")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->
            context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())
            val target: kotlinx.io.unsafe.SegmentWriteContext = context
            val input0: Segment = segment!!
            val input1: Int = 0
            val input2: Byte = 1.toByte()
            val input3: Byte = 2.toByte()
            val input4: Byte = 3.toByte()
            try {
                f01_klib_f570c311693d6703(target, input0, input1, input2, input3, input4)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
                println("state:input1:" + observe(input1))
                println("state:input2:" + observe(input2))
                println("state:input3:" + observe(input3))
                println("state:input4:" + observe(input4))
            }
        4
    }
    println("committed:" + observe(contextBuffer))
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f570c311693d6703")
}

private fun run_klib_f6856a243e61dd47() {
    callbacks = 0
    println("BEGIN:klib-f6856a243e61dd47")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_f6856a243e61dd47(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f6856a243e61dd47")
}

private fun run_klib_f69256afeaa9b7ce() {
    callbacks = 0
    println("BEGIN:klib-f69256afeaa9b7ce")
    try {
        val target: kotlinx.io.Source = seed()
        try {
            f01_klib_f69256afeaa9b7ce(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f69256afeaa9b7ce")
}

private fun run_klib_f6cdd7b8ec302161() {
    callbacks = 0
    println("BEGIN:klib-f6cdd7b8ec302161")
    try {
        try {
            f01_klib_f6cdd7b8ec302161()
        } finally {
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f6cdd7b8ec302161")
}

private fun run_klib_f6fe9eab2b16817b() {
    callbacks = 0
    println("BEGIN:klib-f6fe9eab2b16817b")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.readFromHead(contextBuffer) { context, segment ->
            val target: kotlinx.io.unsafe.SegmentReadContext = context
            try {
                f01_klib_f6fe9eab2b16817b(target)
            } finally {
                println("state:target:" + observe(target))
            }
        0
    }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f6fe9eab2b16817b")
}

private fun run_klib_f721a4a5df2ae655() {
    callbacks = 0
    println("BEGIN:klib-f721a4a5df2ae655")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        val input1: Boolean = false
        try {
            f01_klib_f721a4a5df2ae655(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f721a4a5df2ae655")
}

private fun run_klib_f7b67ed1f0fd800e() {
    callbacks = 0
    println("BEGIN:klib-f7b67ed1f0fd800e")
    try {
        val target: kotlinx.io.Buffer = seed()
        val input0: RawSource = seed()
        val input1: Long = 2L
        try {
            f01_klib_f7b67ed1f0fd800e(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f7b67ed1f0fd800e")
}

private fun run_klib_f7d98255f9d6ecdd() {
    callbacks = 0
    println("BEGIN:klib-f7d98255f9d6ecdd")
    try {
        val input0: ByteString = ByteString(1, 2, 3)
        val input1: Int = 0
        val input2: Int = 2
        try {
            f01_klib_f7d98255f9d6ecdd(input0, input1, input2)
        } finally {
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
            println("state:input2:" + observe(input2))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f7d98255f9d6ecdd")
}

private fun run_klib_f7ee387f61c6a2c0() {
    callbacks = 0
    println("BEGIN:klib-f7ee387f61c6a2c0")
    try {
        val target: kotlinx.io.Buffer = seed()
        try {
            f01_klib_f7ee387f61c6a2c0(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-f7ee387f61c6a2c0")
}

private fun run_klib_fa07a4bb610a4de9() {
    callbacks = 0
    println("BEGIN:klib-fa07a4bb610a4de9")
    try {
        val target: kotlinx.io.Sink = Buffer()
        val input0: RawSource = seed()
        try {
            f01_klib_fa07a4bb610a4de9(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fa07a4bb610a4de9")
}

private fun run_klib_fb2aeb01e083e94f() {
    callbacks = 0
    println("BEGIN:klib-fb2aeb01e083e94f")
    try {
        val target: Source = seed()
        try {
            f01_klib_fb2aeb01e083e94f(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fb2aeb01e083e94f")
}

private fun run_klib_fbc3f88c6499a334() {
    callbacks = 0
    println("BEGIN:klib-fbc3f88c6499a334")
    try {
        val target: ByteString = ByteString(1, 2, 3)
        val input0: ByteString = ByteString(1, 2, 3)
        try {
            f01_klib_fbc3f88c6499a334(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fbc3f88c6499a334")
}

private fun run_klib_fbfc8c4cffccfd8f() {
    callbacks = 0
    println("BEGIN:klib-fbfc8c4cffccfd8f")
    try {
        val target: Source = seed()
        try {
            f01_klib_fbfc8c4cffccfd8f(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fbfc8c4cffccfd8f")
}

private fun run_klib_fc00249c9b381346() {
    callbacks = 0
    println("BEGIN:klib-fc00249c9b381346")
    try {
        val target: Source = seed()
        try {
            f01_klib_fc00249c9b381346(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fc00249c9b381346")
}

private fun run_klib_fc72f439d7d51eff() {
    callbacks = 0
    println("BEGIN:klib-fc72f439d7d51eff")
    try {
        val target: Sink = Buffer()
        val input0: ULong = 1UL
        try {
            f01_klib_fc72f439d7d51eff(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fc72f439d7d51eff")
}

private fun run_klib_fcb3ae8472b429f2() {
    callbacks = 0
    println("BEGIN:klib-fcb3ae8472b429f2")
    try {
        val target: kotlinx.io.RawSource = seed()
        val input0: Buffer = seed()
        val input1: Long = 2L
        try {
            f01_klib_fcb3ae8472b429f2(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fcb3ae8472b429f2")
}

private fun run_klib_fcda5736a2a538fa() {
    callbacks = 0
    println("BEGIN:klib-fcda5736a2a538fa")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        val input1: Path = Path("f02-path")
        try {
            f01_klib_fcda5736a2a538fa(target, input0, input1)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
            println("state:input1:" + observe(input1))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fcda5736a2a538fa")
}

private fun run_klib_fcdd0c8f02bff324() {
    callbacks = 0
    println("BEGIN:klib-fcdd0c8f02bff324")
    try {
        val target: kotlinx.io.files.FileSystem = SystemFileSystem
        val input0: Path = Path("f02-path")
        try {
            f01_klib_fcdd0c8f02bff324(target, input0)
        } finally {
            println("state:target:" + observe(target))
            println("state:input0:" + observe(input0))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fcdd0c8f02bff324")
}

private fun run_klib_fdb3da4587313f8c() {
    callbacks = 0
    println("BEGIN:klib-fdb3da4587313f8c")
    try {
        val contextBuffer = seed()
        UnsafeBufferOperations.writeToTail(contextBuffer, 4) { context, segment ->
            context.setUnchecked(segment, 0, 42.toByte(), 42.toByte(), 42.toByte(), 42.toByte())
            val target: kotlinx.io.unsafe.SegmentWriteContext = context
            val input0: Segment = segment!!
            val input1: Int = 0
            val input2: Byte = 1.toByte()
            val input3: Byte = 2.toByte()
            try {
                f01_klib_fdb3da4587313f8c(target, input0, input1, input2, input3)
            } finally {
                println("state:target:" + observe(target))
                println("state:input0:" + observe(input0))
                println("state:input1:" + observe(input1))
                println("state:input2:" + observe(input2))
                println("state:input3:" + observe(input3))
            }
        4
    }
    println("committed:" + observe(contextBuffer))
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-fdb3da4587313f8c")
}

private fun run_klib_ff236788f8f69617() {
    callbacks = 0
    println("BEGIN:klib-ff236788f8f69617")
    try {
        val target: Source = seed()
        try {
            f01_klib_ff236788f8f69617(target)
        } finally {
            println("state:target:" + observe(target))
        }
        println("exception:none")
    } catch (failure: Throwable) {
        println("exception:" + exceptionType(failure))
    }
    println("callbacks:" + callbacks)
    println("END:klib-ff236788f8f69617")
}

fun main() {
    run_klib_001cc19c43da51fc()
    run_klib_00fa8d5d9f11e43f()
    run_klib_0232231390a7139a()
    run_klib_02a8d87ce59d3a09()
    run_klib_02d81927a9ec9ccf()
    run_klib_02fc8b652c26a1a7()
    run_klib_06ddbce68f82e23e()
    run_klib_07506d12f1446693()
    run_klib_07536a2b0690464c()
    run_klib_07cfd563616534cf()
    run_klib_07f0c52e055ab60c()
    run_klib_0947c0d50c4105d0()
    run_klib_09c8df007d615f43()
    run_klib_09d1def54614dacd()
    run_klib_0b464ce5d17138e9()
    run_klib_0d3d6a9bd110e684()
    run_klib_0e4b69482e6a968a()
    run_klib_0e938793c50b37d6()
    run_klib_0f0ae6b0e4f74922()
    run_klib_11be017879adb524()
    run_klib_122a0905894ba00e()
    run_klib_13c0b806a778aa5c()
    run_klib_1481c81e0f5a5cc4()
    run_klib_14f4f1842013a782()
    run_klib_14fecc4710ddf96c()
    run_klib_18109e8ba4982d6c()
    run_klib_1884b30ae2cabdd7()
    run_klib_191223f6c4e76860()
    run_klib_19a692d1a743b95e()
    run_klib_1cea0040ddde9cf5()
    run_klib_1d66584f002fd45f()
    run_klib_1eab86b635e53e32()
    run_klib_21b369685533b320()
    run_klib_21d678c0082fac12()
    run_klib_234dcde51a17e6be()
    run_klib_287cb83cbbb8abf0()
    run_klib_28ad704738de4392()
    run_klib_28f888234979270b()
    run_klib_293d4e80c1fd216b()
    run_klib_2a3c8fc10ad9fe98()
    run_klib_30f3a5c70398830b()
    run_klib_326c123a5833a082()
    run_klib_3445037415447ceb()
    run_klib_3458721120f74265()
    run_klib_362345f57ba26256()
    run_klib_3849b34106c51c0d()
    run_klib_3892125bf6d12ddd()
    run_klib_3a26229075e48265()
    run_klib_3c68d271a161568d()
    run_klib_3c9070b2e4f85e53()
    run_klib_3d19f06be0624572()
    run_klib_3d41c73755becbfd()
    run_klib_3d59e06c36c0de2c()
    run_klib_3f0132b282858278()
    run_klib_3fa0f868cc4fbb72()
    run_klib_401b5e99cf0a6795()
    run_klib_40e8547b6dd7ad90()
    run_klib_41e3c3eeaaba19c0()
    run_klib_42970e7fff753d0c()
    run_klib_4321c6311cdce9b7()
    run_klib_4366654b667dcd7f()
    run_klib_4709034f040eb8ff()
    run_klib_47da668f67cb4abb()
    run_klib_49fed0452a7d05c0()
    run_klib_4aa81c5400af93fe()
    run_klib_4ab35f2484026657()
    run_klib_4d280feb368bb149()
    run_klib_4d38fa01cf9280a5()
    run_klib_4dad9fe908d53ceb()
    run_klib_4ee0099543291bca()
    run_klib_51d6c72a1f365869()
    run_klib_531fa1db0425b6e0()
    run_klib_539fc5d95ef77842()
    run_klib_53ba821bab96c77e()
    run_klib_54782273b181aa94()
    run_klib_55dcad01b8bc6432()
    run_klib_56c50bf69a16e323()
    run_klib_58329ccccc665665()
    run_klib_5864c1c328005421()
    run_klib_588a0ffe0361140c()
    run_klib_5930fa79e883d19e()
    run_klib_5b4b7a703c6dd6be()
    run_klib_5bdd91ace02d887d()
    run_klib_5d6164d0dc5c0d36()
    run_klib_61d456e1445185b3()
    run_klib_63d334f6656afcd4()
    run_klib_65e6983c396014fe()
    run_klib_67716886daea09d4()
    run_klib_682923f3d5dba325()
    run_klib_68baf701ff31ad9b()
    run_klib_6ac82acec38abefe()
    run_klib_6acf344318aaed3d()
    run_klib_6b0debf09de64260()
    run_klib_6b354812fb812d2e()
    run_klib_6c944335ca7a6f05()
    run_klib_6d6284225d20375c()
    run_klib_6dedd324c4f63d01()
    run_klib_6ec3d2252d99b756()
    run_klib_6f8d15cfbf83da14()
    run_klib_6ffc7a3dfb94a6d5()
    run_klib_71da4182a46d1646()
    run_klib_71f9420a3c56c708()
    run_klib_729acf48b031cbef()
    run_klib_745d0e6a927e88a7()
    run_klib_771b35c257c8cf6a()
    run_klib_77f7b41ec87f091b()
    run_klib_784aceb83262b495()
    run_klib_78eaf273a0fd2845()
    run_klib_7924258da3f788aa()
    run_klib_795e5c923ef63bf3()
    run_klib_7b507920fd698e70()
    run_klib_7be24b4f67123949()
    run_klib_7c6ab4850e567de3()
    run_klib_7dc026044b757651()
    run_klib_7f75d8253eaeafaf()
    run_klib_7fa788e47483b1b4()
    run_klib_8069f1495ab8ee86()
    run_klib_81c0f707fbf38fac()
    run_klib_82806ba38fe9b8f8()
    run_klib_82fdcdfcc61c4db5()
    run_klib_836f7033c3a627e8()
    run_klib_8408acee5eedc7d9()
    run_klib_8493cb924a1ec5ce()
    run_klib_84c73602fe199d0b()
    run_klib_85d81d97b55e0af8()
    run_klib_878bd78d78a70078()
    run_klib_8882e2c069f67a5b()
    run_klib_88bbb664f38f686c()
    run_klib_8a4d65b40a0bf57d()
    run_klib_8ad508ac6d89d176()
    run_klib_8b2ad25426b57149()
    run_klib_8b5e3dc06b358522()
    run_klib_8bffc09edd89a6f5()
    run_klib_8cb9bc77e047d21d()
    run_klib_8eb9402560ac1395()
    run_klib_8f2cd67956fefb8b()
    run_klib_95ecf7a5c44877fd()
    run_klib_97b03a52b446f7a8()
    run_klib_99561fb55e3c6768()
    run_klib_998e3a41ef776da3()
    run_klib_9c9c8d555bae0054()
    run_klib_9d0cebae9efff846()
    run_klib_9d2139e2b8e2d1da()
    run_klib_9f044f29c7d0c7f7()
    run_klib_a00bfbcc6ee356ae()
    run_klib_a0fc40513a876e95()
    run_klib_a547abadbdde0d10()
    run_klib_a6ee175ecb9390e8()
    run_klib_a97fa5c19fd45e36()
    run_klib_a9d4f29aa2f8d0a7()
    run_klib_aada9b079769b5b8()
    run_klib_ac359cf3beddc6af()
    run_klib_ad970e42737004ba()
    run_klib_ae2e25bc70cb0f81()
    run_klib_ae9bd202449ab479()
    run_klib_af3495d0cd999087()
    run_klib_b0cbc86985848be3()
    run_klib_b2e78491a07af06a()
    run_klib_b33ce5b385a93879()
    run_klib_b375c9addf24d27c()
    run_klib_b3c4163f48365984()
    run_klib_b3facb03c7099028()
    run_klib_b4c0c7877dbf9c38()
    run_klib_b6239168ccc071cf()
    run_klib_b7a1e3746605766a()
    run_klib_b8615ffaceb2162f()
    run_klib_b8c0f5c01e53eba4()
    run_klib_b8c4ea47b33d74eb()
    run_klib_b8cef78e807482ab()
    run_klib_b8d3dfb575d2ea24()
    run_klib_b99e5e474e73e737()
    run_klib_ba8f18b87d64cda0()
    run_klib_bb1a86c235fe5d90()
    run_klib_bb9ffc979ba60de7()
    run_klib_bdf28cb8bae382ca()
    run_klib_be8b25c44d1b4769()
    run_klib_c0f160e916c84945()
    run_klib_c16a9382b66a0d92()
    run_klib_c2b35bc7da1ac135()
    run_klib_c43c18bee4ac34f0()
    run_klib_c5967cbbd4139ae7()
    run_klib_c69fb04271e9017f()
    run_klib_c7f1b2f55bd05ce9()
    run_klib_c859368e54032355()
    run_klib_caa6adf5c94ccba4()
    run_klib_cc0b8375fc87baf1()
    run_klib_cd211a43d894fda6()
    run_klib_ce7c92aa2bfb72dc()
    run_klib_cedf0ff273d5d352()
    run_klib_d02d17dc3ff2b0ff()
    run_klib_d1cb273bd1667eae()
    run_klib_d277df79b7105ad5()
    run_klib_d2f38ed9026aca01()
    run_klib_d622a899b3e52773()
    run_klib_da327fd9f523ef4d()
    run_klib_db19efa34d4c840f()
    run_klib_db1be29554216403()
    run_klib_dc06afd6e7388ef3()
    run_klib_defd9573ba737c05()
    run_klib_dfc8f292cc42fe63()
    run_klib_e1f76e75c682b718()
    run_klib_e6692e8ba9801df3()
    run_klib_e73c2ae9564dc892()
    run_klib_e872d95c8706832c()
    run_klib_e8a815654759b526()
    run_klib_ea2a6bf9a5d93882()
    run_klib_ea45816decad6959()
    run_klib_eb2e0cdf209de26a()
    run_klib_ec5be87f1757e6b8()
    run_klib_ee51a94316134963()
    run_klib_ee5d9a571cd8e453()
    run_klib_f10f01d0ac1d5ee1()
    run_klib_f22691bc91e16f23()
    run_klib_f24361849bd7cfdd()
    run_klib_f2a10f7f196b05da()
    run_klib_f570c311693d6703()
    run_klib_f6856a243e61dd47()
    run_klib_f69256afeaa9b7ce()
    run_klib_f6cdd7b8ec302161()
    run_klib_f6fe9eab2b16817b()
    run_klib_f721a4a5df2ae655()
    run_klib_f7b67ed1f0fd800e()
    run_klib_f7d98255f9d6ecdd()
    run_klib_f7ee387f61c6a2c0()
    run_klib_fa07a4bb610a4de9()
    run_klib_fb2aeb01e083e94f()
    run_klib_fbc3f88c6499a334()
    run_klib_fbfc8c4cffccfd8f()
    run_klib_fc00249c9b381346()
    run_klib_fc72f439d7d51eff()
    run_klib_fcb3ae8472b429f2()
    run_klib_fcda5736a2a538fa()
    run_klib_fcdd0c8f02bff324()
    run_klib_fdb3da4587313f8c()
    run_klib_ff236788f8f69617()
}
