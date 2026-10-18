// IO-GATE consumer fixture (ledger and generator retired); edit by hand.
@file:OptIn(
    kotlinx.io.DelicateIoApi::class,
    kotlinx.io.InternalIoApi::class,
    kotlinx.io.UnsafeIoApi::class,
    kotlinx.io.bytestring.unsafe.UnsafeByteStringApi::class,
    kotlin.ExperimentalUnsignedTypes::class,
    kotlin.contracts.ExperimentalContracts::class,
)
package f02ledger
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

// Ledger klib-001cc19c43da51fc: function Source.indexOf(byte: Byte, startIndex: Long = 0L, endIndex: Long = Long.MAX_VALUE): Long
fun f01_klib_001cc19c43da51fc(target: Source, api_arg_0: Byte, api_arg_1: Long, api_arg_2: Long) {
    println("CALL:klib-001cc19c43da51fc:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-001cc19c43da51fc:0")
    println("CALL:klib-001cc19c43da51fc:1")
    try {
        println("value:" + observe(target.indexOf(byte = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-001cc19c43da51fc:1")
}

// Ledger klib-00fa8d5d9f11e43f: function write(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size)
fun f01_klib_00fa8d5d9f11e43f(target: kotlinx.io.Sink, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-00fa8d5d9f11e43f:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-00fa8d5d9f11e43f:0")
    println("CALL:klib-00fa8d5d9f11e43f:1")
    try {
        println("value:" + observe(target.write(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-00fa8d5d9f11e43f:1")
}

// Ledger klib-0232231390a7139a: function emit()
fun f01_klib_0232231390a7139a(target: kotlinx.io.Sink) {
    println("CALL:klib-0232231390a7139a:0")
    try {
        println("value:" + observe(target.emit()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0232231390a7139a:0")
}

// Ledger klib-02a8d87ce59d3a09: function readInt(): Int
fun f01_klib_02a8d87ce59d3a09(target: kotlinx.io.Buffer) {
    println("CALL:klib-02a8d87ce59d3a09:0")
    try {
        println("value:" + observe(target.readInt()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-02a8d87ce59d3a09:0")
}

// Ledger klib-02d81927a9ec9ccf: function write(source: Buffer, byteCount: Long)
fun f01_klib_02d81927a9ec9ccf(target: kotlinx.io.RawSink, api_arg_0: Buffer, api_arg_1: Long) {
    println("CALL:klib-02d81927a9ec9ccf:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-02d81927a9ec9ccf:0")
}

// Ledger klib-02fc8b652c26a1a7: constructor <init>()
fun f01_klib_02fc8b652c26a1a7() {
    println("CALL:klib-02fc8b652c26a1a7:0")
    try {
        println("value:" + observe(kotlinx.io.Buffer()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-02fc8b652c26a1a7:0")
}

// Ledger klib-06ddbce68f82e23e: function Buffer.snapshot(): ByteString
fun f01_klib_06ddbce68f82e23e(target: Buffer) {
    println("CALL:klib-06ddbce68f82e23e:0")
    try {
        println("value:" + observe(target.snapshot()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-06ddbce68f82e23e:0")
}

// Ledger klib-07506d12f1446693: function wrapUnsafe(array: ByteArray): ByteString
fun f01_klib_07506d12f1446693(target: kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations, api_arg_0: ByteArray) {
    println("CALL:klib-07506d12f1446693:0")
    try {
        println("value:" + observe(target.wrapUnsafe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-07506d12f1446693:0")
}

// Ledger klib-07536a2b0690464c: function SegmentReadContext.withData( segment: Segment, readAction: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Unit )
fun f01_klib_07536a2b0690464c(target: SegmentReadContext, api_arg_0: Segment, api_arg_1: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Unit) {
    println("CALL:klib-07536a2b0690464c:0")
    try {
        println("value:" + observe(target.withData(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-07536a2b0690464c:0")
}

// Ledger klib-07cfd563616534cf: function hashCode(): Int
fun f01_klib_07cfd563616534cf(target: kotlinx.io.files.Path) {
    println("CALL:klib-07cfd563616534cf:0")
    try {
        println("value:" + observe(target.hashCode()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-07cfd563616534cf:0")
}

// Ledger klib-07f0c52e055ab60c: function Base64.encodeToAppendable( source: ByteString, destination: A, startIndex: Int = 0, endIndex: Int = source.size ): A
fun <A : Appendable> f01_klib_07f0c52e055ab60c(api_arg_0: ByteString, api_arg_1: A, api_arg_2: Int, api_arg_3: Int) {
    println("CALL:klib-07f0c52e055ab60c:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeToAppendable(api_arg_0, api_arg_1, api_arg_2, api_arg_3)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-07f0c52e055ab60c:0")
    println("CALL:klib-07f0c52e055ab60c:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeToAppendable(source = api_arg_0, destination = api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-07f0c52e055ab60c:1")
}

// Ledger klib-0947c0d50c4105d0: function writeInt(int: Int)
fun f01_klib_0947c0d50c4105d0(target: kotlinx.io.Sink, api_arg_0: Int) {
    println("CALL:klib-0947c0d50c4105d0:0")
    try {
        println("value:" + observe(target.writeInt(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0947c0d50c4105d0:0")
}

// Ledger klib-09c8df007d615f43: annotation class InternalIoApi
@kotlinx.io.InternalIoApi
fun f01_klib_09c8df007d615f43() {
}

// Ledger klib-09d1def54614dacd: function ByteString.indexOf(byteArray: ByteArray, startIndex: Int = 0): Int
fun f01_klib_09d1def54614dacd(target: ByteString, api_arg_0: ByteArray, api_arg_1: Int) {
    println("CALL:klib-09d1def54614dacd:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-09d1def54614dacd:0")
    println("CALL:klib-09d1def54614dacd:1")
    try {
        println("value:" + observe(target.indexOf(byteArray = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-09d1def54614dacd:1")
}

// Ledger klib-0b464ce5d17138e9: interface Sink
fun f01_klib_0b464ce5d17138e9(value: kotlinx.io.Sink) {
    println("CALL:klib-0b464ce5d17138e9:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0b464ce5d17138e9:0")
}

// Ledger klib-0d3d6a9bd110e684: function readInt(): Int
fun f01_klib_0d3d6a9bd110e684(target: kotlinx.io.Source) {
    println("CALL:klib-0d3d6a9bd110e684:0")
    try {
        println("value:" + observe(target.readInt()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0d3d6a9bd110e684:0")
}

// Ledger klib-0e4b69482e6a968a: function Sink.writeFloatLe(float: Float)
fun f01_klib_0e4b69482e6a968a(target: Sink, api_arg_0: Float) {
    println("CALL:klib-0e4b69482e6a968a:0")
    try {
        println("value:" + observe(target.writeFloatLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0e4b69482e6a968a:0")
}

// Ledger klib-0e938793c50b37d6: function readShort(): Short
fun f01_klib_0e938793c50b37d6(target: kotlinx.io.Buffer) {
    println("CALL:klib-0e938793c50b37d6:0")
    try {
        println("value:" + observe(target.readShort()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0e938793c50b37d6:0")
}

// Ledger klib-0f0ae6b0e4f74922: object UnsafeBufferOperations
fun f01_klib_0f0ae6b0e4f74922() {
    println("CALL:klib-0f0ae6b0e4f74922:0")
    try {
        println("value:" + observe(kotlinx.io.unsafe.UnsafeBufferOperations))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-0f0ae6b0e4f74922:0")
}

// Ledger klib-11be017879adb524: function readAtMostTo(sink: ByteArray, startIndex: Int, endIndex: Int): Int
fun f01_klib_11be017879adb524(target: kotlinx.io.Buffer, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-11be017879adb524:0")
    try {
        println("value:" + observe(target.readAtMostTo(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-11be017879adb524:0")
}

// Ledger klib-122a0905894ba00e: function setUnchecked(segment: Segment, offset: Int, b0: Byte, b1: Byte, b2: Byte, b3: Byte)
fun f01_klib_122a0905894ba00e(target: kotlinx.io.unsafe.SegmentWriteContext, api_arg_0: Segment, api_arg_1: Int, api_arg_2: Byte, api_arg_3: Byte, api_arg_4: Byte, api_arg_5: Byte) {
    println("CALL:klib-122a0905894ba00e:0")
    try {
        println("value:" + observe(target.setUnchecked(api_arg_0, api_arg_1, api_arg_2, api_arg_3, api_arg_4, api_arg_5)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-122a0905894ba00e:0")
}

// Ledger klib-13c0b806a778aa5c: function Source.readCodePointValue(): Int
fun f01_klib_13c0b806a778aa5c(target: Source) {
    println("CALL:klib-13c0b806a778aa5c:0")
    try {
        println("value:" + observe(target.readCodePointValue()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-13c0b806a778aa5c:0")
}

// Ledger klib-1481c81e0f5a5cc4: function readFromHead(buffer: Buffer, readAction: (SegmentReadContext, Segment) -> Int): Int
fun f01_klib_1481c81e0f5a5cc4(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: (SegmentReadContext, Segment) -> Int) {
    println("CALL:klib-1481c81e0f5a5cc4:0")
    try {
        println("value:" + observe(target.readFromHead(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1481c81e0f5a5cc4:0")
}

// Ledger klib-14f4f1842013a782: function copyInto( destination: ByteArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = size )
fun f01_klib_14f4f1842013a782(target: kotlinx.io.bytestring.ByteString, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int, api_arg_3: Int) {
    println("CALL:klib-14f4f1842013a782:0")
    try {
        println("value:" + observe(target.copyInto(api_arg_0, api_arg_1, api_arg_2, api_arg_3)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-14f4f1842013a782:0")
    println("CALL:klib-14f4f1842013a782:1")
    try {
        println("value:" + observe(target.copyInto(destination = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-14f4f1842013a782:1")
}

// Ledger klib-14fecc4710ddf96c: function iterate( buffer: Buffer, iterationAction: (context: BufferIterationContext, head: Segment?) -> Unit )
fun f01_klib_14fecc4710ddf96c(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: (context: BufferIterationContext, head: Segment?) -> Unit) {
    println("CALL:klib-14fecc4710ddf96c:0")
    try {
        println("value:" + observe(target.iterate(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-14fecc4710ddf96c:0")
}

// Ledger klib-18109e8ba4982d6c: function Source.readByteArray(): ByteArray
fun f01_klib_18109e8ba4982d6c(target: Source) {
    println("CALL:klib-18109e8ba4982d6c:0")
    try {
        println("value:" + observe(target.readByteArray()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-18109e8ba4982d6c:0")
}

// Ledger klib-1884b30ae2cabdd7: function Source.readTo(sink: ByteArray, startIndex: Int = 0, endIndex: Int = sink.size)
fun f01_klib_1884b30ae2cabdd7(target: Source, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-1884b30ae2cabdd7:0")
    try {
        println("value:" + observe(target.readTo(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1884b30ae2cabdd7:0")
    println("CALL:klib-1884b30ae2cabdd7:1")
    try {
        println("value:" + observe(target.readTo(sink = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1884b30ae2cabdd7:1")
}

// Ledger klib-191223f6c4e76860: function Source.readString(byteCount: Long): String
fun f01_klib_191223f6c4e76860(target: Source, api_arg_0: Long) {
    println("CALL:klib-191223f6c4e76860:0")
    try {
        println("value:" + observe(target.readString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-191223f6c4e76860:0")
}

// Ledger klib-19a692d1a743b95e: function delete(path: Path, mustExist: Boolean = true)
fun f01_klib_19a692d1a743b95e(target: kotlinx.io.files.FileSystem, api_arg_0: Path, api_arg_1: Boolean) {
    println("CALL:klib-19a692d1a743b95e:0")
    try {
        println("value:" + observe(target.delete(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-19a692d1a743b95e:0")
    println("CALL:klib-19a692d1a743b95e:1")
    try {
        println("value:" + observe(target.delete(path = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-19a692d1a743b95e:1")
}

// Ledger klib-1cea0040ddde9cf5: val SystemPathSeparator: Char
fun f01_klib_1cea0040ddde9cf5() {
    println("CALL:klib-1cea0040ddde9cf5:0")
    try {
        println("value:" + observe(kotlinx.io.files.SystemPathSeparator))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1cea0040ddde9cf5:0")
}

// Ledger klib-1d66584f002fd45f: val size: Int
fun f01_klib_1d66584f002fd45f(target: kotlinx.io.Segment) {
    println("CALL:klib-1d66584f002fd45f:0")
    try {
        println("value:" + observe(target.size))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1d66584f002fd45f:0")
}

// Ledger klib-1eab86b635e53e32: function Sink.writeUByte(byte: UByte)
fun f01_klib_1eab86b635e53e32(target: Sink, api_arg_0: UByte) {
    println("CALL:klib-1eab86b635e53e32:0")
    try {
        println("value:" + observe(target.writeUByte(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-1eab86b635e53e32:0")
}

// Ledger klib-21b369685533b320: function skip(byteCount: Long)
fun f01_klib_21b369685533b320(target: kotlinx.io.Buffer, api_arg_0: Long) {
    println("CALL:klib-21b369685533b320:0")
    try {
        println("value:" + observe(target.skip(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-21b369685533b320:0")
}

// Ledger klib-21d678c0082fac12: function Sink.writeUInt(int: UInt)
fun f01_klib_21d678c0082fac12(target: Sink, api_arg_0: UInt) {
    println("CALL:klib-21d678c0082fac12:0")
    try {
        println("value:" + observe(target.writeUInt(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-21d678c0082fac12:0")
}

// Ledger klib-234dcde51a17e6be: function toString(): String
fun f01_klib_234dcde51a17e6be(target: kotlinx.io.bytestring.ByteString) {
    println("CALL:klib-234dcde51a17e6be:0")
    try {
        println("value:" + observe(target.toString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-234dcde51a17e6be:0")
}

// Ledger klib-287cb83cbbb8abf0: function write(source: Buffer, byteCount: Long)
fun f01_klib_287cb83cbbb8abf0(target: kotlinx.io.Buffer, api_arg_0: Buffer, api_arg_1: Long) {
    println("CALL:klib-287cb83cbbb8abf0:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-287cb83cbbb8abf0:0")
}

// Ledger klib-28ad704738de4392: function get(position: Long): Byte
fun f01_klib_28ad704738de4392(target: kotlinx.io.Buffer, api_arg_0: Long) {
    println("CALL:klib-28ad704738de4392:0")
    try {
        println("value:" + observe(target.get(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-28ad704738de4392:0")
}

// Ledger klib-28f888234979270b: function Sink.writeUShortLe(short: UShort)
fun f01_klib_28f888234979270b(target: Sink, api_arg_0: UShort) {
    println("CALL:klib-28f888234979270b:0")
    try {
        println("value:" + observe(target.writeUShortLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-28f888234979270b:0")
}

// Ledger klib-293d4e80c1fd216b: function substring(startIndex: Int, endIndex: Int = size): ByteString
fun f01_klib_293d4e80c1fd216b(target: kotlinx.io.bytestring.ByteString, api_arg_0: Int, api_arg_1: Int) {
    println("CALL:klib-293d4e80c1fd216b:0")
    try {
        println("value:" + observe(target.substring(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-293d4e80c1fd216b:0")
    println("CALL:klib-293d4e80c1fd216b:1")
    try {
        println("value:" + observe(target.substring(startIndex = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-293d4e80c1fd216b:1")
}

// Ledger klib-2a3c8fc10ad9fe98: function sink(path: Path, append: Boolean = false): RawSink
fun f01_klib_2a3c8fc10ad9fe98(target: kotlinx.io.files.FileSystem, api_arg_0: Path, api_arg_1: Boolean) {
    println("CALL:klib-2a3c8fc10ad9fe98:0")
    try {
        println("value:" + observe(target.sink(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-2a3c8fc10ad9fe98:0")
    println("CALL:klib-2a3c8fc10ad9fe98:1")
    try {
        println("value:" + observe(target.sink(path = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-2a3c8fc10ad9fe98:1")
}

// Ledger klib-30f3a5c70398830b: function Base64.decodeIntoByteArray( source: ByteString, destination: ByteArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = source.size ): Int
fun f01_klib_30f3a5c70398830b(api_arg_0: ByteString, api_arg_1: ByteArray, api_arg_2: Int, api_arg_3: Int, api_arg_4: Int) {
    println("CALL:klib-30f3a5c70398830b:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeIntoByteArray(api_arg_0, api_arg_1, api_arg_2, api_arg_3, api_arg_4)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-30f3a5c70398830b:0")
    println("CALL:klib-30f3a5c70398830b:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeIntoByteArray(source = api_arg_0, destination = api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-30f3a5c70398830b:1")
}

// Ledger klib-326c123a5833a082: function resolve(path: Path): Path
fun f01_klib_326c123a5833a082(target: kotlinx.io.files.FileSystem, api_arg_0: Path) {
    println("CALL:klib-326c123a5833a082:0")
    try {
        println("value:" + observe(target.resolve(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-326c123a5833a082:0")
}

// Ledger klib-3445037415447ceb: function write(source: ByteArray, startIndex: Int, endIndex: Int)
fun f01_klib_3445037415447ceb(target: kotlinx.io.Buffer, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-3445037415447ceb:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3445037415447ceb:0")
}

// Ledger klib-3458721120f74265: function close()
fun f01_klib_3458721120f74265(target: kotlinx.io.RawSink) {
    println("CALL:klib-3458721120f74265:0")
    try {
        println("value:" + observe(target.close()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3458721120f74265:0")
}

// Ledger klib-362345f57ba26256: function toString(): String
fun f01_klib_362345f57ba26256(target: kotlinx.io.files.Path) {
    println("CALL:klib-362345f57ba26256:0")
    try {
        println("value:" + observe(target.toString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-362345f57ba26256:0")
}

// Ledger klib-3849b34106c51c0d: function Source.readString(): String
fun f01_klib_3849b34106c51c0d(target: Source) {
    println("CALL:klib-3849b34106c51c0d:0")
    try {
        println("value:" + observe(target.readString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3849b34106c51c0d:0")
}

// Ledger klib-3892125bf6d12ddd: function Source.readUIntLe(): UInt
fun f01_klib_3892125bf6d12ddd(target: Source) {
    println("CALL:klib-3892125bf6d12ddd:0")
    try {
        println("value:" + observe(target.readUIntLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3892125bf6d12ddd:0")
}

// Ledger klib-3a26229075e48265: function ByteString.lastIndexOf(byteString: ByteString, startIndex: Int = 0): Int
fun f01_klib_3a26229075e48265(target: ByteString, api_arg_0: ByteString, api_arg_1: Int) {
    println("CALL:klib-3a26229075e48265:0")
    try {
        println("value:" + observe(target.lastIndexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3a26229075e48265:0")
    println("CALL:klib-3a26229075e48265:1")
    try {
        println("value:" + observe(target.lastIndexOf(byteString = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3a26229075e48265:1")
}

// Ledger klib-3c68d271a161568d: function Source.readByteString(byteCount: Int): ByteString
fun f01_klib_3c68d271a161568d(target: Source, api_arg_0: Int) {
    println("CALL:klib-3c68d271a161568d:0")
    try {
        println("value:" + observe(target.readByteString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3c68d271a161568d:0")
}

// Ledger klib-3c9070b2e4f85e53: val isDirectory: Boolean
fun f01_klib_3c9070b2e4f85e53(target: kotlinx.io.files.FileMetadata) {
    println("CALL:klib-3c9070b2e4f85e53:0")
    try {
        println("value:" + observe(target.isDirectory))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3c9070b2e4f85e53:0")
}

// Ledger klib-3d19f06be0624572: class Buffer
fun f01_klib_3d19f06be0624572(value: kotlinx.io.Buffer) {
    println("CALL:klib-3d19f06be0624572:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3d19f06be0624572:0")
}

// Ledger klib-3d41c73755becbfd: function writeShort(short: Short)
fun f01_klib_3d41c73755becbfd(target: kotlinx.io.Sink, api_arg_0: Short) {
    println("CALL:klib-3d41c73755becbfd:0")
    try {
        println("value:" + observe(target.writeShort(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3d41c73755becbfd:0")
}

// Ledger klib-3d59e06c36c0de2c: function ByteString.isEmpty(): Boolean
fun f01_klib_3d59e06c36c0de2c(target: ByteString) {
    println("CALL:klib-3d59e06c36c0de2c:0")
    try {
        println("value:" + observe(target.isEmpty()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3d59e06c36c0de2c:0")
}

// Ledger klib-3f0132b282858278: interface BufferIterationContext
fun f01_klib_3f0132b282858278(value: kotlinx.io.unsafe.BufferIterationContext) {
    println("CALL:klib-3f0132b282858278:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3f0132b282858278:0")
}

// Ledger klib-3fa0f868cc4fbb72: function flush()
fun f01_klib_3fa0f868cc4fbb72(target: kotlinx.io.Sink) {
    println("CALL:klib-3fa0f868cc4fbb72:0")
    try {
        println("value:" + observe(target.flush()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-3fa0f868cc4fbb72:0")
}

// Ledger klib-401b5e99cf0a6795: function ByteString(vararg bytes: Byte): ByteString
fun f01_klib_401b5e99cf0a6795(api_arg_0: Byte) {
    println("CALL:klib-401b5e99cf0a6795:0")
    try {
        println("value:" + observe(ByteString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-401b5e99cf0a6795:0")
}

// Ledger klib-40e8547b6dd7ad90: function ByteString.lastIndexOf(byte: Byte, startIndex: Int = 0): Int
fun f01_klib_40e8547b6dd7ad90(target: ByteString, api_arg_0: Byte, api_arg_1: Int) {
    println("CALL:klib-40e8547b6dd7ad90:0")
    try {
        println("value:" + observe(target.lastIndexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-40e8547b6dd7ad90:0")
    println("CALL:klib-40e8547b6dd7ad90:1")
    try {
        println("value:" + observe(target.lastIndexOf(byte = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-40e8547b6dd7ad90:1")
}

// Ledger klib-41e3c3eeaaba19c0: function Sink.writeToInternalBuffer(lambda: (Buffer) -> Unit)
fun f01_klib_41e3c3eeaaba19c0(target: Sink, api_arg_0: (Buffer) -> Unit) {
    println("CALL:klib-41e3c3eeaaba19c0:0")
    try {
        println("value:" + observe(target.writeToInternalBuffer(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-41e3c3eeaaba19c0:0")
}

// Ledger klib-42970e7fff753d0c: function readLong(): Long
fun f01_klib_42970e7fff753d0c(target: kotlinx.io.Buffer) {
    println("CALL:klib-42970e7fff753d0c:0")
    try {
        println("value:" + observe(target.readLong()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-42970e7fff753d0c:0")
}

// Ledger klib-4321c6311cdce9b7: val isAbsolute: Boolean
fun f01_klib_4321c6311cdce9b7(target: kotlinx.io.files.Path) {
    println("CALL:klib-4321c6311cdce9b7:0")
    try {
        println("value:" + observe(target.isAbsolute))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4321c6311cdce9b7:0")
}

// Ledger klib-4366654b667dcd7f: function Buffer.readString(): String
fun f01_klib_4366654b667dcd7f(target: Buffer) {
    println("CALL:klib-4366654b667dcd7f:0")
    try {
        println("value:" + observe(target.readString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4366654b667dcd7f:0")
}

// Ledger klib-4709034f040eb8ff: function source(path: Path): RawSource
fun f01_klib_4709034f040eb8ff(target: kotlinx.io.files.FileSystem, api_arg_0: Path) {
    println("CALL:klib-4709034f040eb8ff:0")
    try {
        println("value:" + observe(target.source(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4709034f040eb8ff:0")
}

// Ledger klib-47da668f67cb4abb: function ByteString.contentEquals(array: ByteArray): Boolean
fun f01_klib_47da668f67cb4abb(target: ByteString, api_arg_0: ByteArray) {
    println("CALL:klib-47da668f67cb4abb:0")
    try {
        println("value:" + observe(target.contentEquals(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-47da668f67cb4abb:0")
}

// Ledger klib-49fed0452a7d05c0: function writeInt(int: Int)
fun f01_klib_49fed0452a7d05c0(target: kotlinx.io.Buffer, api_arg_0: Int) {
    println("CALL:klib-49fed0452a7d05c0:0")
    try {
        println("value:" + observe(target.writeInt(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-49fed0452a7d05c0:0")
}

// Ledger klib-4aa81c5400af93fe: val remainingCapacity: Int
fun f01_klib_4aa81c5400af93fe(target: kotlinx.io.Segment) {
    println("CALL:klib-4aa81c5400af93fe:0")
    try {
        println("value:" + observe(target.remainingCapacity))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4aa81c5400af93fe:0")
}

// Ledger klib-4ab35f2484026657: class Segment
fun f01_klib_4ab35f2484026657(value: kotlinx.io.Segment) {
    println("CALL:klib-4ab35f2484026657:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4ab35f2484026657:0")
}

// Ledger klib-4d280feb368bb149: function ByteString.toHexString(format: HexFormat = HexFormat.Default): String
fun f01_klib_4d280feb368bb149(target: ByteString, api_arg_0: HexFormat) {
    println("CALL:klib-4d280feb368bb149:0")
    try {
        println("value:" + observe(target.toHexString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4d280feb368bb149:0")
    println("CALL:klib-4d280feb368bb149:1")
    try {
        println("value:" + observe(target.toHexString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4d280feb368bb149:1")
}

// Ledger klib-4d38fa01cf9280a5: function Base64.decodeToByteString(source: ByteArray, startIndex: Int = 0, endIndex: Int = source.size): ByteString
fun f01_klib_4d38fa01cf9280a5(api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-4d38fa01cf9280a5:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4d38fa01cf9280a5:0")
    println("CALL:klib-4d38fa01cf9280a5:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4d38fa01cf9280a5:1")
}

// Ledger klib-4dad9fe908d53ceb: function writeLong(long: Long)
fun f01_klib_4dad9fe908d53ceb(target: kotlinx.io.Buffer, api_arg_0: Long) {
    println("CALL:klib-4dad9fe908d53ceb:0")
    try {
        println("value:" + observe(target.writeLong(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4dad9fe908d53ceb:0")
}

// Ledger klib-4ee0099543291bca: interface SegmentWriteContext
fun f01_klib_4ee0099543291bca(value: kotlinx.io.unsafe.SegmentWriteContext) {
    println("CALL:klib-4ee0099543291bca:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-4ee0099543291bca:0")
}

// Ledger klib-51d6c72a1f365869: function writeByte(byte: Byte)
fun f01_klib_51d6c72a1f365869(target: kotlinx.io.Sink, api_arg_0: Byte) {
    println("CALL:klib-51d6c72a1f365869:0")
    try {
        println("value:" + observe(target.writeByte(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-51d6c72a1f365869:0")
}

// Ledger klib-531fa1db0425b6e0: function String.hexToByteString(format: HexFormat = HexFormat.Default): ByteString
fun f01_klib_531fa1db0425b6e0(target: String, api_arg_0: HexFormat) {
    println("CALL:klib-531fa1db0425b6e0:0")
    try {
        println("value:" + observe(target.hexToByteString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-531fa1db0425b6e0:0")
    println("CALL:klib-531fa1db0425b6e0:1")
    try {
        println("value:" + observe(target.hexToByteString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-531fa1db0425b6e0:1")
}

// Ledger klib-539fc5d95ef77842: interface FileSystem
fun f01_klib_539fc5d95ef77842(value: kotlinx.io.files.FileSystem) {
    println("CALL:klib-539fc5d95ef77842:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-539fc5d95ef77842:0")
}

// Ledger klib-53ba821bab96c77e: function require(byteCount: Long)
fun f01_klib_53ba821bab96c77e(target: kotlinx.io.Buffer, api_arg_0: Long) {
    println("CALL:klib-53ba821bab96c77e:0")
    try {
        println("value:" + observe(target.require(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-53ba821bab96c77e:0")
}

// Ledger klib-54782273b181aa94: function toByteArray(startIndex: Int = 0, endIndex: Int = size): ByteArray
fun f01_klib_54782273b181aa94(target: kotlinx.io.bytestring.ByteString, api_arg_0: Int, api_arg_1: Int) {
    println("CALL:klib-54782273b181aa94:0")
    try {
        println("value:" + observe(target.toByteArray(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-54782273b181aa94:0")
    println("CALL:klib-54782273b181aa94:1")
    try {
        println("value:" + observe(target.toByteArray()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-54782273b181aa94:1")
}

// Ledger klib-55dcad01b8bc6432: interface RawSource
fun f01_klib_55dcad01b8bc6432(value: kotlinx.io.RawSource) {
    println("CALL:klib-55dcad01b8bc6432:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-55dcad01b8bc6432:0")
}

// Ledger klib-56c50bf69a16e323: function Source.readUByte(): UByte
fun f01_klib_56c50bf69a16e323(target: Source) {
    println("CALL:klib-56c50bf69a16e323:0")
    try {
        println("value:" + observe(target.readUByte()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-56c50bf69a16e323:0")
}

// Ledger klib-58329ccccc665665: function Source.readFloatLe(): Float
fun f01_klib_58329ccccc665665(target: Source) {
    println("CALL:klib-58329ccccc665665:0")
    try {
        println("value:" + observe(target.readFloatLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-58329ccccc665665:0")
}

// Ledger klib-5864c1c328005421: function Source.indexOf(byteString: ByteString, startIndex: Long = 0): Long
fun f01_klib_5864c1c328005421(target: Source, api_arg_0: ByteString, api_arg_1: Long) {
    println("CALL:klib-5864c1c328005421:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5864c1c328005421:0")
    println("CALL:klib-5864c1c328005421:1")
    try {
        println("value:" + observe(target.indexOf(byteString = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5864c1c328005421:1")
}

// Ledger klib-588a0ffe0361140c: constructor <init>(data: ByteArray, startIndex: Int = 0, endIndex: Int = data.size)
fun f01_klib_588a0ffe0361140c(api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-588a0ffe0361140c:0")
    try {
        println("value:" + observe(kotlinx.io.bytestring.ByteString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-588a0ffe0361140c:0")
    println("CALL:klib-588a0ffe0361140c:1")
    try {
        println("value:" + observe(kotlinx.io.bytestring.ByteString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-588a0ffe0361140c:1")
}

// Ledger klib-5930fa79e883d19e: function copy(): Buffer
fun f01_klib_5930fa79e883d19e(target: kotlinx.io.Buffer) {
    println("CALL:klib-5930fa79e883d19e:0")
    try {
        println("value:" + observe(target.copy()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5930fa79e883d19e:0")
}

// Ledger klib-5b4b7a703c6dd6be: function Source.readLineStrict(limit: Long = Long.MAX_VALUE): String
fun f01_klib_5b4b7a703c6dd6be(target: Source, api_arg_0: Long) {
    println("CALL:klib-5b4b7a703c6dd6be:0")
    try {
        println("value:" + observe(target.readLineStrict(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5b4b7a703c6dd6be:0")
    println("CALL:klib-5b4b7a703c6dd6be:1")
    try {
        println("value:" + observe(target.readLineStrict()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5b4b7a703c6dd6be:1")
}

// Ledger klib-5bdd91ace02d887d: function list(directory: Path): Collection<Path>
fun f01_klib_5bdd91ace02d887d(target: kotlinx.io.files.FileSystem, api_arg_0: Path) {
    println("CALL:klib-5bdd91ace02d887d:0")
    try {
        println("value:" + observe(target.list(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5bdd91ace02d887d:0")
}

// Ledger klib-5d6164d0dc5c0d36: function compareTo(other: ByteString): Int
fun f01_klib_5d6164d0dc5c0d36(target: kotlinx.io.bytestring.ByteString, api_arg_0: ByteString) {
    println("CALL:klib-5d6164d0dc5c0d36:0")
    try {
        println("value:" + observe(target.compareTo(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-5d6164d0dc5c0d36:0")
}

// Ledger klib-61d456e1445185b3: function Base64.encodeIntoByteArray( source: ByteString, destination: ByteArray, destinationOffset: Int = 0, startIndex: Int = 0, endIndex: Int = source.size ): Int
fun f01_klib_61d456e1445185b3(api_arg_0: ByteString, api_arg_1: ByteArray, api_arg_2: Int, api_arg_3: Int, api_arg_4: Int) {
    println("CALL:klib-61d456e1445185b3:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeIntoByteArray(api_arg_0, api_arg_1, api_arg_2, api_arg_3, api_arg_4)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-61d456e1445185b3:0")
    println("CALL:klib-61d456e1445185b3:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeIntoByteArray(source = api_arg_0, destination = api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-61d456e1445185b3:1")
}

// Ledger klib-63d334f6656afcd4: function emit(): Unit
fun f01_klib_63d334f6656afcd4(target: kotlinx.io.Buffer) {
    println("CALL:klib-63d334f6656afcd4:0")
    try {
        println("value:" + observe(target.emit()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-63d334f6656afcd4:0")
}

// Ledger klib-65e6983c396014fe: function request(byteCount: Long): Boolean
fun f01_klib_65e6983c396014fe(target: kotlinx.io.Buffer, api_arg_0: Long) {
    println("CALL:klib-65e6983c396014fe:0")
    try {
        println("value:" + observe(target.request(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-65e6983c396014fe:0")
}

// Ledger klib-67716886daea09d4: function Path(base: Path, vararg parts: String): Path
fun f01_klib_67716886daea09d4(api_arg_0: Path, api_arg_1: String) {
    println("CALL:klib-67716886daea09d4:0")
    try {
        println("value:" + observe(Path(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-67716886daea09d4:0")
}

// Ledger klib-682923f3d5dba325: val buffer: Buffer
fun f01_klib_682923f3d5dba325(target: kotlinx.io.Source) {
    println("CALL:klib-682923f3d5dba325:0")
    try {
        println("value:" + observe(target.buffer))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-682923f3d5dba325:0")
}

// Ledger klib-68baf701ff31ad9b: function Source.readUShort(): UShort
fun f01_klib_68baf701ff31ad9b(target: Source) {
    println("CALL:klib-68baf701ff31ad9b:0")
    try {
        println("value:" + observe(target.readUShort()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-68baf701ff31ad9b:0")
}

// Ledger klib-6ac82acec38abefe: class ByteString
fun f01_klib_6ac82acec38abefe(value: kotlinx.io.bytestring.ByteString) {
    println("CALL:klib-6ac82acec38abefe:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6ac82acec38abefe:0")
}

// Ledger klib-6acf344318aaed3d: function Sink.writeULongLe(long: ULong)
fun f01_klib_6acf344318aaed3d(target: Sink, api_arg_0: ULong) {
    println("CALL:klib-6acf344318aaed3d:0")
    try {
        println("value:" + observe(target.writeULongLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6acf344318aaed3d:0")
}

// Ledger klib-6b0debf09de64260: function readAtMostTo(sink: ByteArray, startIndex: Int = 0, endIndex: Int = sink.size): Int
fun f01_klib_6b0debf09de64260(target: kotlinx.io.Source, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-6b0debf09de64260:0")
    try {
        println("value:" + observe(target.readAtMostTo(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6b0debf09de64260:0")
    println("CALL:klib-6b0debf09de64260:1")
    try {
        println("value:" + observe(target.readAtMostTo(sink = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6b0debf09de64260:1")
}

// Ledger klib-6b354812fb812d2e: class Path
fun f01_klib_6b354812fb812d2e(value: kotlinx.io.files.Path) {
    println("CALL:klib-6b354812fb812d2e:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6b354812fb812d2e:0")
}

// Ledger klib-6c944335ca7a6f05: function Source.readULongLe(): ULong
fun f01_klib_6c944335ca7a6f05(target: Source) {
    println("CALL:klib-6c944335ca7a6f05:0")
    try {
        println("value:" + observe(target.readULongLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6c944335ca7a6f05:0")
}

// Ledger klib-6d6284225d20375c: function Sink.writeUShort(short: UShort)
fun f01_klib_6d6284225d20375c(target: Sink, api_arg_0: UShort) {
    println("CALL:klib-6d6284225d20375c:0")
    try {
        println("value:" + observe(target.writeUShort(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6d6284225d20375c:0")
}

// Ledger klib-6dedd324c4f63d01: function next(segment: Segment): Segment?
fun f01_klib_6dedd324c4f63d01(target: kotlinx.io.unsafe.BufferIterationContext, api_arg_0: Segment) {
    println("CALL:klib-6dedd324c4f63d01:0")
    try {
        println("value:" + observe(target.next(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6dedd324c4f63d01:0")
}

// Ledger klib-6ec3d2252d99b756: function hintEmit(): Unit
fun f01_klib_6ec3d2252d99b756(target: kotlinx.io.Buffer) {
    println("CALL:klib-6ec3d2252d99b756:0")
    try {
        println("value:" + observe(target.hintEmit()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6ec3d2252d99b756:0")
}

// Ledger klib-6f8d15cfbf83da14: function ByteString.indexOf(byte: Byte, startIndex: Int = 0): Int
fun f01_klib_6f8d15cfbf83da14(target: ByteString, api_arg_0: Byte, api_arg_1: Int) {
    println("CALL:klib-6f8d15cfbf83da14:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6f8d15cfbf83da14:0")
    println("CALL:klib-6f8d15cfbf83da14:1")
    try {
        println("value:" + observe(target.indexOf(byte = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6f8d15cfbf83da14:1")
}

// Ledger klib-6ffc7a3dfb94a6d5: function Source.readLongLe(): Long
fun f01_klib_6ffc7a3dfb94a6d5(target: Source) {
    println("CALL:klib-6ffc7a3dfb94a6d5:0")
    try {
        println("value:" + observe(target.readLongLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-6ffc7a3dfb94a6d5:0")
}

// Ledger klib-71da4182a46d1646: function Sink.writeDecimalLong(long: Long)
fun f01_klib_71da4182a46d1646(target: Sink, api_arg_0: Long) {
    println("CALL:klib-71da4182a46d1646:0")
    try {
        println("value:" + observe(target.writeDecimalLong(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-71da4182a46d1646:0")
}

// Ledger klib-71f9420a3c56c708: function hashCode(): Int
fun f01_klib_71f9420a3c56c708(target: kotlinx.io.bytestring.ByteString) {
    println("CALL:klib-71f9420a3c56c708:0")
    try {
        println("value:" + observe(target.hashCode()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-71f9420a3c56c708:0")
}

// Ledger klib-729acf48b031cbef: function readTo(sink: RawSink, byteCount: Long)
fun f01_klib_729acf48b031cbef(target: kotlinx.io.Buffer, api_arg_0: RawSink, api_arg_1: Long) {
    println("CALL:klib-729acf48b031cbef:0")
    try {
        println("value:" + observe(target.readTo(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-729acf48b031cbef:0")
}

// Ledger klib-745d0e6a927e88a7: function write(source: RawSource, byteCount: Long)
fun f01_klib_745d0e6a927e88a7(target: kotlinx.io.Sink, api_arg_0: RawSource, api_arg_1: Long) {
    println("CALL:klib-745d0e6a927e88a7:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-745d0e6a927e88a7:0")
}

// Ledger klib-771b35c257c8cf6a: function get(index: Int): Byte
fun f01_klib_771b35c257c8cf6a(target: kotlinx.io.bytestring.ByteString, api_arg_0: Int) {
    println("CALL:klib-771b35c257c8cf6a:0")
    try {
        println("value:" + observe(target.get(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-771b35c257c8cf6a:0")
}

// Ledger klib-77f7b41ec87f091b: function Sink.writeDoubleLe(double: Double)
fun f01_klib_77f7b41ec87f091b(target: Sink, api_arg_0: Double) {
    println("CALL:klib-77f7b41ec87f091b:0")
    try {
        println("value:" + observe(target.writeDoubleLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-77f7b41ec87f091b:0")
}

// Ledger klib-784aceb83262b495: function ByteString.startsWith(byteString: ByteString): Boolean
fun f01_klib_784aceb83262b495(target: ByteString, api_arg_0: ByteString) {
    println("CALL:klib-784aceb83262b495:0")
    try {
        println("value:" + observe(target.startsWith(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-784aceb83262b495:0")
}

// Ledger klib-78eaf273a0fd2845: function Source.startsWith(byte: Byte): Boolean
fun f01_klib_78eaf273a0fd2845(target: Source, api_arg_0: Byte) {
    println("CALL:klib-78eaf273a0fd2845:0")
    try {
        println("value:" + observe(target.startsWith(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-78eaf273a0fd2845:0")
}

// Ledger klib-7924258da3f788aa: function toByteString(): ByteString
fun f01_klib_7924258da3f788aa(target: kotlinx.io.bytestring.ByteStringBuilder) {
    println("CALL:klib-7924258da3f788aa:0")
    try {
        println("value:" + observe(target.toByteString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7924258da3f788aa:0")
}

// Ledger klib-795e5c923ef63bf3: interface Source
fun f01_klib_795e5c923ef63bf3(value: kotlinx.io.Source) {
    println("CALL:klib-795e5c923ef63bf3:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-795e5c923ef63bf3:0")
}

// Ledger klib-7b507920fd698e70: function readFromHead( buffer: Buffer, readAction: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int ): Int
fun f01_klib_7b507920fd698e70(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int) {
    println("CALL:klib-7b507920fd698e70:0")
    try {
        println("value:" + observe(target.readFromHead(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7b507920fd698e70:0")
}

// Ledger klib-7be24b4f67123949: function ByteStringBuilder.append(byte: UByte): Unit
fun f01_klib_7be24b4f67123949(target: ByteStringBuilder, api_arg_0: UByte) {
    println("CALL:klib-7be24b4f67123949:0")
    try {
        println("value:" + observe(target.append(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7be24b4f67123949:0")
}

// Ledger klib-7c6ab4850e567de3: function hintEmit()
fun f01_klib_7c6ab4850e567de3(target: kotlinx.io.Sink) {
    println("CALL:klib-7c6ab4850e567de3:0")
    try {
        println("value:" + observe(target.hintEmit()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7c6ab4850e567de3:0")
}

// Ledger klib-7dc026044b757651: function ByteStringBuilder.append(byteString: ByteString)
fun f01_klib_7dc026044b757651(target: ByteStringBuilder, api_arg_0: ByteString) {
    println("CALL:klib-7dc026044b757651:0")
    try {
        println("value:" + observe(target.append(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7dc026044b757651:0")
}

// Ledger klib-7f75d8253eaeafaf: function writeLong(long: Long)
fun f01_klib_7f75d8253eaeafaf(target: kotlinx.io.Sink, api_arg_0: Long) {
    println("CALL:klib-7f75d8253eaeafaf:0")
    try {
        println("value:" + observe(target.writeLong(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7f75d8253eaeafaf:0")
}

// Ledger klib-7fa788e47483b1b4: val buffer: Buffer
fun f01_klib_7fa788e47483b1b4(target: kotlinx.io.Sink) {
    println("CALL:klib-7fa788e47483b1b4:0")
    try {
        println("value:" + observe(target.buffer))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-7fa788e47483b1b4:0")
}

// Ledger klib-8069f1495ab8ee86: function Path(path: String): Path
fun f01_klib_8069f1495ab8ee86(api_arg_0: String) {
    println("CALL:klib-8069f1495ab8ee86:0")
    try {
        println("value:" + observe(Path(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8069f1495ab8ee86:0")
}

// Ledger klib-81c0f707fbf38fac: function Base64.encode( source: ByteString, startIndex: Int = 0, endIndex: Int = source.size ): String
fun f01_klib_81c0f707fbf38fac(api_arg_0: ByteString, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-81c0f707fbf38fac:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encode(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-81c0f707fbf38fac:0")
    println("CALL:klib-81c0f707fbf38fac:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encode(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-81c0f707fbf38fac:1")
}

// Ledger klib-82806ba38fe9b8f8: function ByteString.toHexString( startIndex: Int = 0, endIndex: Int = size, format: HexFormat = HexFormat.Default ): String
fun f01_klib_82806ba38fe9b8f8(target: ByteString, api_arg_0: Int, api_arg_1: Int, api_arg_2: HexFormat) {
    println("CALL:klib-82806ba38fe9b8f8:0")
    try {
        println("value:" + observe(target.toHexString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-82806ba38fe9b8f8:0")
    println("CALL:klib-82806ba38fe9b8f8:1")
    try {
        println("value:" + observe(target.toHexString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-82806ba38fe9b8f8:1")
}

// Ledger klib-82fdcdfcc61c4db5: function request(byteCount: Long): Boolean
fun f01_klib_82fdcdfcc61c4db5(target: kotlinx.io.Source, api_arg_0: Long) {
    println("CALL:klib-82fdcdfcc61c4db5:0")
    try {
        println("value:" + observe(target.request(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-82fdcdfcc61c4db5:0")
}

// Ledger klib-836f7033c3a627e8: function Sink.writeCodePointValue(codePoint: Int): Unit
fun f01_klib_836f7033c3a627e8(target: Sink, api_arg_0: Int) {
    println("CALL:klib-836f7033c3a627e8:0")
    try {
        println("value:" + observe(target.writeCodePointValue(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-836f7033c3a627e8:0")
}

// Ledger klib-8408acee5eedc7d9: function getUnchecked(segment: Segment, offset: Int): Byte
fun f01_klib_8408acee5eedc7d9(target: kotlinx.io.unsafe.SegmentReadContext, api_arg_0: Segment, api_arg_1: Int) {
    println("CALL:klib-8408acee5eedc7d9:0")
    try {
        println("value:" + observe(target.getUnchecked(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8408acee5eedc7d9:0")
}

// Ledger klib-8493cb924a1ec5ce: function readTo(sink: RawSink, byteCount: Long)
fun f01_klib_8493cb924a1ec5ce(target: kotlinx.io.Source, api_arg_0: RawSink, api_arg_1: Long) {
    println("CALL:klib-8493cb924a1ec5ce:0")
    try {
        println("value:" + observe(target.readTo(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8493cb924a1ec5ce:0")
}

// Ledger klib-84c73602fe199d0b: function skip(byteCount: Long)
fun f01_klib_84c73602fe199d0b(target: kotlinx.io.Source, api_arg_0: Long) {
    println("CALL:klib-84c73602fe199d0b:0")
    try {
        println("value:" + observe(target.skip(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-84c73602fe199d0b:0")
}

// Ledger klib-85d81d97b55e0af8: function ByteString.indexOf(byteString: ByteString, startIndex: Int = 0): Int
fun f01_klib_85d81d97b55e0af8(target: ByteString, api_arg_0: ByteString, api_arg_1: Int) {
    println("CALL:klib-85d81d97b55e0af8:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-85d81d97b55e0af8:0")
    println("CALL:klib-85d81d97b55e0af8:1")
    try {
        println("value:" + observe(target.indexOf(byteString = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-85d81d97b55e0af8:1")
}

// Ledger klib-878bd78d78a70078: val maxSafeWriteCapacity: Int
fun f01_klib_878bd78d78a70078(target: kotlinx.io.unsafe.UnsafeBufferOperations) {
    println("CALL:klib-878bd78d78a70078:0")
    try {
        println("value:" + observe(target.maxSafeWriteCapacity))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-878bd78d78a70078:0")
}

// Ledger klib-8882e2c069f67a5b: function RawSink.buffered(): Sink
fun f01_klib_8882e2c069f67a5b(target: RawSink) {
    println("CALL:klib-8882e2c069f67a5b:0")
    try {
        println("value:" + observe(target.buffered()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8882e2c069f67a5b:0")
}

// Ledger klib-88bbb664f38f686c: function readLong(): Long
fun f01_klib_88bbb664f38f686c(target: kotlinx.io.Source) {
    println("CALL:klib-88bbb664f38f686c:0")
    try {
        println("value:" + observe(target.readLong()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-88bbb664f38f686c:0")
}

// Ledger klib-8a4d65b40a0bf57d: function readByte(): Byte
fun f01_klib_8a4d65b40a0bf57d(target: kotlinx.io.Source) {
    println("CALL:klib-8a4d65b40a0bf57d:0")
    try {
        println("value:" + observe(target.readByte()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8a4d65b40a0bf57d:0")
}

// Ledger klib-8ad508ac6d89d176: constructor <init>( /** * Flag indicating that the metadata was retrieved for a regular file. */ public val isRegularFile: Boolean = false, /** * Flag indicating that the metadata was retrieved for a directory. */ public val isDirectory: Boolean = false, /** * File size. Defined only for regular files, for other filesystem entities it will be `-1`. */ public val size: Long = 0L )
fun f01_klib_8ad508ac6d89d176(api_arg_0: Boolean, api_arg_1: Boolean, api_arg_2: Long) {
    println("CALL:klib-8ad508ac6d89d176:0")
    try {
        println("value:" + observe(kotlinx.io.files.FileMetadata(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8ad508ac6d89d176:0")
    println("CALL:klib-8ad508ac6d89d176:1")
    try {
        println("value:" + observe(kotlinx.io.files.FileMetadata()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8ad508ac6d89d176:1")
}

// Ledger klib-8b2ad25426b57149: function equals(other: Any?): Boolean
fun f01_klib_8b2ad25426b57149(target: kotlinx.io.files.Path, api_arg_0: Any?) {
    println("CALL:klib-8b2ad25426b57149:0")
    try {
        println("value:" + observe(target.equals(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8b2ad25426b57149:0")
}

// Ledger klib-8b5e3dc06b358522: val size: Int
fun f01_klib_8b5e3dc06b358522(target: kotlinx.io.bytestring.ByteStringBuilder) {
    println("CALL:klib-8b5e3dc06b358522:0")
    try {
        println("value:" + observe(target.size))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8b5e3dc06b358522:0")
}

// Ledger klib-8bffc09edd89a6f5: function Source.readDecimalLong(): Long
fun f01_klib_8bffc09edd89a6f5(target: Source) {
    println("CALL:klib-8bffc09edd89a6f5:0")
    try {
        println("value:" + observe(target.readDecimalLong()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8bffc09edd89a6f5:0")
}

// Ledger klib-8cb9bc77e047d21d: function transferTo(sink: RawSink): Long
fun f01_klib_8cb9bc77e047d21d(target: kotlinx.io.Source, api_arg_0: RawSink) {
    println("CALL:klib-8cb9bc77e047d21d:0")
    try {
        println("value:" + observe(target.transferTo(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8cb9bc77e047d21d:0")
}

// Ledger klib-8eb9402560ac1395: val indices: IntRange
fun f01_klib_8eb9402560ac1395(target: ByteString) {
    println("CALL:klib-8eb9402560ac1395:0")
    try {
        println("value:" + observe(target.indices))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8eb9402560ac1395:0")
}

// Ledger klib-8f2cd67956fefb8b: function Buffer.indexOf(byte: Byte, startIndex: Long = 0, endIndex: Long = size): Long
fun f01_klib_8f2cd67956fefb8b(target: Buffer, api_arg_0: Byte, api_arg_1: Long, api_arg_2: Long) {
    println("CALL:klib-8f2cd67956fefb8b:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8f2cd67956fefb8b:0")
    println("CALL:klib-8f2cd67956fefb8b:1")
    try {
        println("value:" + observe(target.indexOf(byte = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-8f2cd67956fefb8b:1")
}

// Ledger klib-95ecf7a5c44877fd: function ByteString.startsWith(byteArray: ByteArray): Boolean
fun f01_klib_95ecf7a5c44877fd(target: ByteString, api_arg_0: ByteArray) {
    println("CALL:klib-95ecf7a5c44877fd:0")
    try {
        println("value:" + observe(target.startsWith(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-95ecf7a5c44877fd:0")
}

// Ledger klib-97b03a52b446f7a8: function equals(other: Any?): Boolean
fun f01_klib_97b03a52b446f7a8(target: kotlinx.io.bytestring.ByteString, api_arg_0: Any?) {
    println("CALL:klib-97b03a52b446f7a8:0")
    try {
        println("value:" + observe(target.equals(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-97b03a52b446f7a8:0")
}

// Ledger klib-99561fb55e3c6768: function Sink.writeShortLe(short: Short)
fun f01_klib_99561fb55e3c6768(target: Sink, api_arg_0: Short) {
    println("CALL:klib-99561fb55e3c6768:0")
    try {
        println("value:" + observe(target.writeShortLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-99561fb55e3c6768:0")
}

// Ledger klib-998e3a41ef776da3: class FileMetadata
fun f01_klib_998e3a41ef776da3(value: kotlinx.io.files.FileMetadata) {
    println("CALL:klib-998e3a41ef776da3:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-998e3a41ef776da3:0")
}

// Ledger klib-9c9c8d555bae0054: val isRegularFile: Boolean
fun f01_klib_9c9c8d555bae0054(target: kotlinx.io.files.FileMetadata) {
    println("CALL:klib-9c9c8d555bae0054:0")
    try {
        println("value:" + observe(target.isRegularFile))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-9c9c8d555bae0054:0")
}

// Ledger klib-9d0cebae9efff846: function flush()
fun f01_klib_9d0cebae9efff846(target: kotlinx.io.RawSink) {
    println("CALL:klib-9d0cebae9efff846:0")
    try {
        println("value:" + observe(target.flush()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-9d0cebae9efff846:0")
}

// Ledger klib-9d2139e2b8e2d1da: function Path(base: String, vararg parts: String): Path
fun f01_klib_9d2139e2b8e2d1da(api_arg_0: String, api_arg_1: String) {
    println("CALL:klib-9d2139e2b8e2d1da:0")
    try {
        println("value:" + observe(Path(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-9d2139e2b8e2d1da:0")
}

// Ledger klib-9f044f29c7d0c7f7: function forEachSegment( buffer: Buffer, action: (context: SegmentReadContext, segment: Segment) -> Unit )
fun f01_klib_9f044f29c7d0c7f7(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: (context: SegmentReadContext, segment: Segment) -> Unit) {
    println("CALL:klib-9f044f29c7d0c7f7:0")
    try {
        println("value:" + observe(target.forEachSegment(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-9f044f29c7d0c7f7:0")
}

// Ledger klib-a00bfbcc6ee356ae: function writeToTail( buffer: Buffer, minimumCapacity: Int, writeAction: (context: SegmentWriteContext, tail: Segment) -> Int ): Int
fun f01_klib_a00bfbcc6ee356ae(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: Int, api_arg_2: (context: SegmentWriteContext, tail: Segment) -> Int) {
    println("CALL:klib-a00bfbcc6ee356ae:0")
    try {
        println("value:" + observe(target.writeToTail(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a00bfbcc6ee356ae:0")
}

// Ledger klib-a0fc40513a876e95: function clear(): Unit
fun f01_klib_a0fc40513a876e95(target: kotlinx.io.Buffer) {
    println("CALL:klib-a0fc40513a876e95:0")
    try {
        println("value:" + observe(target.clear()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a0fc40513a876e95:0")
}

// Ledger klib-a547abadbdde0d10: val size: Long
fun f01_klib_a547abadbdde0d10(target: kotlinx.io.files.FileMetadata) {
    println("CALL:klib-a547abadbdde0d10:0")
    try {
        println("value:" + observe(target.size))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a547abadbdde0d10:0")
}

// Ledger klib-a6ee175ecb9390e8: function Source.readByteString(): ByteString
fun f01_klib_a6ee175ecb9390e8(target: Source) {
    println("CALL:klib-a6ee175ecb9390e8:0")
    try {
        println("value:" + observe(target.readByteString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a6ee175ecb9390e8:0")
}

// Ledger klib-a97fa5c19fd45e36: function Source.readDoubleLe(): Double
fun f01_klib_a97fa5c19fd45e36(target: Source) {
    println("CALL:klib-a97fa5c19fd45e36:0")
    try {
        println("value:" + observe(target.readDoubleLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a97fa5c19fd45e36:0")
}

// Ledger klib-a9d4f29aa2f8d0a7: function ByteString.endsWith(byteArray: ByteArray): Boolean
fun f01_klib_a9d4f29aa2f8d0a7(target: ByteString, api_arg_0: ByteArray) {
    println("CALL:klib-a9d4f29aa2f8d0a7:0")
    try {
        println("value:" + observe(target.endsWith(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-a9d4f29aa2f8d0a7:0")
}

// Ledger klib-aada9b079769b5b8: function Base64.decodeToByteString(source: CharSequence, startIndex: Int = 0, endIndex: Int = source.length): ByteString
fun f01_klib_aada9b079769b5b8(api_arg_0: CharSequence, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-aada9b079769b5b8:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-aada9b079769b5b8:0")
    println("CALL:klib-aada9b079769b5b8:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-aada9b079769b5b8:1")
}

// Ledger klib-ac359cf3beddc6af: function Source.readShortLe(): Short
fun f01_klib_ac359cf3beddc6af(target: Source) {
    println("CALL:klib-ac359cf3beddc6af:0")
    try {
        println("value:" + observe(target.readShortLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ac359cf3beddc6af:0")
}

// Ledger klib-ad970e42737004ba: function copyTo( out: Buffer, startIndex: Long = 0L, endIndex: Long = size )
fun f01_klib_ad970e42737004ba(target: kotlinx.io.Buffer, api_arg_0: Buffer, api_arg_1: Long, api_arg_2: Long) {
    println("CALL:klib-ad970e42737004ba:0")
    try {
        println("value:" + observe(target.copyTo(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ad970e42737004ba:0")
    println("CALL:klib-ad970e42737004ba:1")
    try {
        println("value:" + observe(target.copyTo(out = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ad970e42737004ba:1")
}

// Ledger klib-ae2e25bc70cb0f81: function Sink.writeDouble(double: Double)
fun f01_klib_ae2e25bc70cb0f81(target: Sink, api_arg_0: Double) {
    println("CALL:klib-ae2e25bc70cb0f81:0")
    try {
        println("value:" + observe(target.writeDouble(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ae2e25bc70cb0f81:0")
}

// Ledger klib-ae9bd202449ab479: function append(array: ByteArray, startIndex: Int = 0, endIndex: Int = array.size)
fun f01_klib_ae9bd202449ab479(target: kotlinx.io.bytestring.ByteStringBuilder, api_arg_0: ByteArray, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-ae9bd202449ab479:0")
    try {
        println("value:" + observe(target.append(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ae9bd202449ab479:0")
    println("CALL:klib-ae9bd202449ab479:1")
    try {
        println("value:" + observe(target.append(array = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ae9bd202449ab479:1")
}

// Ledger klib-af3495d0cd999087: val parent: Path?
fun f01_klib_af3495d0cd999087(target: kotlinx.io.files.Path) {
    println("CALL:klib-af3495d0cd999087:0")
    try {
        println("value:" + observe(target.parent))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-af3495d0cd999087:0")
}

// Ledger klib-b0cbc86985848be3: function Source.readByteArray(byteCount: Int): ByteArray
fun f01_klib_b0cbc86985848be3(target: Source, api_arg_0: Int) {
    println("CALL:klib-b0cbc86985848be3:0")
    try {
        println("value:" + observe(target.readByteArray(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b0cbc86985848be3:0")
}

// Ledger klib-b2e78491a07af06a: function writeToTail( buffer: Buffer, minimumCapacity: Int, writeAction: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int ): Int
fun f01_klib_b2e78491a07af06a(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: Int, api_arg_2: (bytes: ByteArray, startIndexInclusive: Int, endIndexExclusive: Int) -> Int) {
    println("CALL:klib-b2e78491a07af06a:0")
    try {
        println("value:" + observe(target.writeToTail(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b2e78491a07af06a:0")
}

// Ledger klib-b33ce5b385a93879: function Buffer.indexOf(byteString: ByteString, startIndex: Long = 0): Long
fun f01_klib_b33ce5b385a93879(target: Buffer, api_arg_0: ByteString, api_arg_1: Long) {
    println("CALL:klib-b33ce5b385a93879:0")
    try {
        println("value:" + observe(target.indexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b33ce5b385a93879:0")
    println("CALL:klib-b33ce5b385a93879:1")
    try {
        println("value:" + observe(target.indexOf(byteString = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b33ce5b385a93879:1")
}

// Ledger klib-b375c9addf24d27c: function toString(): String
fun f01_klib_b375c9addf24d27c(target: kotlinx.io.Buffer) {
    println("CALL:klib-b375c9addf24d27c:0")
    try {
        println("value:" + observe(target.toString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b375c9addf24d27c:0")
}

// Ledger klib-b3c4163f48365984: object Companion
fun f01_klib_b3c4163f48365984() {
    println("CALL:klib-b3c4163f48365984:0")
    try {
        println("value:" + observe(kotlinx.io.bytestring.ByteString.Companion))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b3c4163f48365984:0")
}

// Ledger klib-b3facb03c7099028: function withByteArrayUnsafe(byteString: ByteString, block: (ByteArray) -> Unit)
fun f01_klib_b3facb03c7099028(target: kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations, api_arg_0: ByteString, api_arg_1: (ByteArray) -> Unit) {
    println("CALL:klib-b3facb03c7099028:0")
    try {
        println("value:" + observe(target.withByteArrayUnsafe(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b3facb03c7099028:0")
}

// Ledger klib-b4c0c7877dbf9c38: function Source.readIntLe(): Int
fun f01_klib_b4c0c7877dbf9c38(target: Source) {
    println("CALL:klib-b4c0c7877dbf9c38:0")
    try {
        println("value:" + observe(target.readIntLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b4c0c7877dbf9c38:0")
}

// Ledger klib-b6239168ccc071cf: function Sink.writeFloat(float: Float)
fun f01_klib_b6239168ccc071cf(target: Sink, api_arg_0: Float) {
    println("CALL:klib-b6239168ccc071cf:0")
    try {
        println("value:" + observe(target.writeFloat(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b6239168ccc071cf:0")
}

// Ledger klib-b7a1e3746605766a: function Sink.write(byteString: ByteString, startIndex: Int = 0, endIndex: Int = byteString.size)
fun f01_klib_b7a1e3746605766a(target: Sink, api_arg_0: ByteString, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-b7a1e3746605766a:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b7a1e3746605766a:0")
    println("CALL:klib-b7a1e3746605766a:1")
    try {
        println("value:" + observe(target.write(byteString = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b7a1e3746605766a:1")
}

// Ledger klib-b8615ffaceb2162f: function setUnchecked(segment: Segment, offset: Int, value: Byte)
fun f01_klib_b8615ffaceb2162f(target: kotlinx.io.unsafe.SegmentWriteContext, api_arg_0: Segment, api_arg_1: Int, api_arg_2: Byte) {
    println("CALL:klib-b8615ffaceb2162f:0")
    try {
        println("value:" + observe(target.setUnchecked(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8615ffaceb2162f:0")
}

// Ledger klib-b8c0f5c01e53eba4: function ByteStringBuilder.append(vararg bytes: Byte): Unit
fun f01_klib_b8c0f5c01e53eba4(target: ByteStringBuilder, api_arg_0: Byte) {
    println("CALL:klib-b8c0f5c01e53eba4:0")
    try {
        println("value:" + observe(target.append(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8c0f5c01e53eba4:0")
}

// Ledger klib-b8c4ea47b33d74eb: function ByteString.lastIndexOf(byteArray: ByteArray, startIndex: Int = 0): Int
fun f01_klib_b8c4ea47b33d74eb(target: ByteString, api_arg_0: ByteArray, api_arg_1: Int) {
    println("CALL:klib-b8c4ea47b33d74eb:0")
    try {
        println("value:" + observe(target.lastIndexOf(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8c4ea47b33d74eb:0")
    println("CALL:klib-b8c4ea47b33d74eb:1")
    try {
        println("value:" + observe(target.lastIndexOf(byteArray = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8c4ea47b33d74eb:1")
}

// Ledger klib-b8cef78e807482ab: function Source.readHexadecimalUnsignedLong(): Long
fun f01_klib_b8cef78e807482ab(target: Source) {
    println("CALL:klib-b8cef78e807482ab:0")
    try {
        println("value:" + observe(target.readHexadecimalUnsignedLong()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8cef78e807482ab:0")
}

// Ledger klib-b8d3dfb575d2ea24: interface RawSink
fun f01_klib_b8d3dfb575d2ea24(value: kotlinx.io.RawSink) {
    println("CALL:klib-b8d3dfb575d2ea24:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b8d3dfb575d2ea24:0")
}

// Ledger klib-b99e5e474e73e737: function exists(path: Path): Boolean
fun f01_klib_b99e5e474e73e737(target: kotlinx.io.files.FileSystem, api_arg_0: Path) {
    println("CALL:klib-b99e5e474e73e737:0")
    try {
        println("value:" + observe(target.exists(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-b99e5e474e73e737:0")
}

// Ledger klib-ba8f18b87d64cda0: val name: String
fun f01_klib_ba8f18b87d64cda0(target: kotlinx.io.files.Path) {
    println("CALL:klib-ba8f18b87d64cda0:0")
    try {
        println("value:" + observe(target.name))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ba8f18b87d64cda0:0")
}

// Ledger klib-bb1a86c235fe5d90: class ByteStringBuilder
fun f01_klib_bb1a86c235fe5d90(value: kotlinx.io.bytestring.ByteStringBuilder) {
    println("CALL:klib-bb1a86c235fe5d90:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-bb1a86c235fe5d90:0")
}

// Ledger klib-bb9ffc979ba60de7: function Source.readUInt(): UInt
fun f01_klib_bb9ffc979ba60de7(target: Source) {
    println("CALL:klib-bb9ffc979ba60de7:0")
    try {
        println("value:" + observe(target.readUInt()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-bb9ffc979ba60de7:0")
}

// Ledger klib-bdf28cb8bae382ca: function close()
fun f01_klib_bdf28cb8bae382ca(target: kotlinx.io.RawSource) {
    println("CALL:klib-bdf28cb8bae382ca:0")
    try {
        println("value:" + observe(target.close()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-bdf28cb8bae382ca:0")
}

// Ledger klib-be8b25c44d1b4769: function ByteString.decodeToString(): String
fun f01_klib_be8b25c44d1b4769(target: ByteString) {
    println("CALL:klib-be8b25c44d1b4769:0")
    try {
        println("value:" + observe(target.decodeToString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-be8b25c44d1b4769:0")
}

// Ledger klib-c0f160e916c84945: function ByteString(): ByteString
fun f01_klib_c0f160e916c84945() {
    println("CALL:klib-c0f160e916c84945:0")
    try {
        println("value:" + observe(ByteString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c0f160e916c84945:0")
}

// Ledger klib-c16a9382b66a0d92: annotation class UnsafeIoApi
@kotlinx.io.UnsafeIoApi
fun f01_klib_c16a9382b66a0d92() {
}

// Ledger klib-c2b35bc7da1ac135: function exhausted(): Boolean
fun f01_klib_c2b35bc7da1ac135(target: kotlinx.io.Source) {
    println("CALL:klib-c2b35bc7da1ac135:0")
    try {
        println("value:" + observe(target.exhausted()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c2b35bc7da1ac135:0")
}

// Ledger klib-c43c18bee4ac34f0: constructor <init>(initialCapacity: Int = 0)
fun f01_klib_c43c18bee4ac34f0(api_arg_0: Int) {
    println("CALL:klib-c43c18bee4ac34f0:0")
    try {
        println("value:" + observe(kotlinx.io.bytestring.ByteStringBuilder(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c43c18bee4ac34f0:0")
    println("CALL:klib-c43c18bee4ac34f0:1")
    try {
        println("value:" + observe(kotlinx.io.bytestring.ByteStringBuilder()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c43c18bee4ac34f0:1")
}

// Ledger klib-c5967cbbd4139ae7: function require(byteCount: Long)
fun f01_klib_c5967cbbd4139ae7(target: kotlinx.io.Source, api_arg_0: Long) {
    println("CALL:klib-c5967cbbd4139ae7:0")
    try {
        println("value:" + observe(target.require(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c5967cbbd4139ae7:0")
}

// Ledger klib-c69fb04271e9017f: function flush(): Unit
fun f01_klib_c69fb04271e9017f(target: kotlinx.io.Buffer) {
    println("CALL:klib-c69fb04271e9017f:0")
    try {
        println("value:" + observe(target.flush()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c69fb04271e9017f:0")
}

// Ledger klib-c7f1b2f55bd05ce9: function String.encodeToByteString(): ByteString
fun f01_klib_c7f1b2f55bd05ce9(target: String) {
    println("CALL:klib-c7f1b2f55bd05ce9:0")
    try {
        println("value:" + observe(target.encodeToByteString()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c7f1b2f55bd05ce9:0")
}

// Ledger klib-c859368e54032355: function Base64.encodeToByteArray(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteArray
fun f01_klib_c859368e54032355(api_arg_0: ByteString, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-c859368e54032355:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeToByteArray(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c859368e54032355:0")
    println("CALL:klib-c859368e54032355:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.encodeToByteArray(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-c859368e54032355:1")
}

// Ledger klib-caa6adf5c94ccba4: function iterate( buffer: Buffer, offset: Long, iterationAction: (context: BufferIterationContext, segment: Segment?, startOfTheSegmentOffset: Long) -> Unit )
fun f01_klib_caa6adf5c94ccba4(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: Long, api_arg_2: (context: BufferIterationContext, segment: Segment?, startOfTheSegmentOffset: Long) -> Unit) {
    println("CALL:klib-caa6adf5c94ccba4:0")
    try {
        println("value:" + observe(target.iterate(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-caa6adf5c94ccba4:0")
}

// Ledger klib-cc0b8375fc87baf1: function Sink.writeIntLe(int: Int)
fun f01_klib_cc0b8375fc87baf1(target: Sink, api_arg_0: Int) {
    println("CALL:klib-cc0b8375fc87baf1:0")
    try {
        println("value:" + observe(target.writeIntLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-cc0b8375fc87baf1:0")
}

// Ledger klib-cd211a43d894fda6: function close(): Unit
fun f01_klib_cd211a43d894fda6(target: kotlinx.io.Buffer) {
    println("CALL:klib-cd211a43d894fda6:0")
    try {
        println("value:" + observe(target.close()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-cd211a43d894fda6:0")
}

// Ledger klib-ce7c92aa2bfb72dc: val SystemLineSeparator: String
fun f01_klib_ce7c92aa2bfb72dc() {
    println("CALL:klib-ce7c92aa2bfb72dc:0")
    try {
        println("value:" + observe(kotlinx.io.SystemLineSeparator))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ce7c92aa2bfb72dc:0")
}

// Ledger klib-cedf0ff273d5d352: function moveToTail(buffer: Buffer, bytes: ByteArray, startIndex: Int = 0, endIndex: Int = bytes.size)
fun f01_klib_cedf0ff273d5d352(target: kotlinx.io.unsafe.UnsafeBufferOperations, api_arg_0: Buffer, api_arg_1: ByteArray, api_arg_2: Int, api_arg_3: Int) {
    println("CALL:klib-cedf0ff273d5d352:0")
    try {
        println("value:" + observe(target.moveToTail(api_arg_0, api_arg_1, api_arg_2, api_arg_3)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-cedf0ff273d5d352:0")
    println("CALL:klib-cedf0ff273d5d352:1")
    try {
        println("value:" + observe(target.moveToTail(buffer = api_arg_0, bytes = api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-cedf0ff273d5d352:1")
}

// Ledger klib-d02d17dc3ff2b0ff: val size: Long
fun f01_klib_d02d17dc3ff2b0ff(target: kotlinx.io.Buffer) {
    println("CALL:klib-d02d17dc3ff2b0ff:0")
    try {
        println("value:" + observe(target.size))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d02d17dc3ff2b0ff:0")
}

// Ledger klib-d1cb273bd1667eae: function ByteString(vararg bytes: UByte): ByteString
fun f01_klib_d1cb273bd1667eae(api_arg_0: UByte) {
    println("CALL:klib-d1cb273bd1667eae:0")
    try {
        println("value:" + observe(ByteString(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d1cb273bd1667eae:0")
}

// Ledger klib-d277df79b7105ad5: function buildByteString(capacity: Int = 0, builderAction: ByteStringBuilder.() -> Unit): ByteString
fun f01_klib_d277df79b7105ad5(api_arg_0: Int, api_arg_1: ByteStringBuilder.() -> Unit) {
    println("CALL:klib-d277df79b7105ad5:0")
    try {
        println("value:" + observe(buildByteString(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d277df79b7105ad5:0")
    println("CALL:klib-d277df79b7105ad5:1")
    try {
        println("value:" + observe(buildByteString(builderAction = api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d277df79b7105ad5:1")
}

// Ledger klib-d2f38ed9026aca01: function Sink.writeString(chars: CharSequence, startIndex: Int = 0, endIndex: Int = chars.length)
fun f01_klib_d2f38ed9026aca01(target: Sink, api_arg_0: CharSequence, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-d2f38ed9026aca01:0")
    try {
        println("value:" + observe(target.writeString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d2f38ed9026aca01:0")
    println("CALL:klib-d2f38ed9026aca01:1")
    try {
        println("value:" + observe(target.writeString(chars = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d2f38ed9026aca01:1")
}

// Ledger klib-d622a899b3e52773: function Sink.writeUIntLe(int: UInt)
fun f01_klib_d622a899b3e52773(target: Sink, api_arg_0: UInt) {
    println("CALL:klib-d622a899b3e52773:0")
    try {
        println("value:" + observe(target.writeUIntLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-d622a899b3e52773:0")
}

// Ledger klib-da327fd9f523ef4d: function peek(): Source
fun f01_klib_da327fd9f523ef4d(target: kotlinx.io.Buffer) {
    println("CALL:klib-da327fd9f523ef4d:0")
    try {
        println("value:" + observe(target.peek()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-da327fd9f523ef4d:0")
}

// Ledger klib-db19efa34d4c840f: function writeShort(short: Short)
fun f01_klib_db19efa34d4c840f(target: kotlinx.io.Buffer, api_arg_0: Short) {
    println("CALL:klib-db19efa34d4c840f:0")
    try {
        println("value:" + observe(target.writeShort(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-db19efa34d4c840f:0")
}

// Ledger klib-db1be29554216403: function Sink.writeHexadecimalUnsignedLong(long: Long)
fun f01_klib_db1be29554216403(target: Sink, api_arg_0: Long) {
    println("CALL:klib-db1be29554216403:0")
    try {
        println("value:" + observe(target.writeHexadecimalUnsignedLong(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-db1be29554216403:0")
}

// Ledger klib-dc06afd6e7388ef3: val capacity: Int
fun f01_klib_dc06afd6e7388ef3(target: kotlinx.io.bytestring.ByteStringBuilder) {
    println("CALL:klib-dc06afd6e7388ef3:0")
    try {
        println("value:" + observe(target.capacity))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-dc06afd6e7388ef3:0")
}

// Ledger klib-defd9573ba737c05: function Source.readULong(): ULong
fun f01_klib_defd9573ba737c05(target: Source) {
    println("CALL:klib-defd9573ba737c05:0")
    try {
        println("value:" + observe(target.readULong()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-defd9573ba737c05:0")
}

// Ledger klib-dfc8f292cc42fe63: function Sink.writeLongLe(long: Long)
fun f01_klib_dfc8f292cc42fe63(target: Sink, api_arg_0: Long) {
    println("CALL:klib-dfc8f292cc42fe63:0")
    try {
        println("value:" + observe(target.writeLongLe(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-dfc8f292cc42fe63:0")
}

// Ledger klib-e1f76e75c682b718: val buffer: Buffer
fun f01_klib_e1f76e75c682b718(target: kotlinx.io.Buffer) {
    println("CALL:klib-e1f76e75c682b718:0")
    try {
        println("value:" + observe(target.buffer))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-e1f76e75c682b718:0")
}

// Ledger klib-e6692e8ba9801df3: function RawSource.buffered(): Source
fun f01_klib_e6692e8ba9801df3(target: RawSource) {
    println("CALL:klib-e6692e8ba9801df3:0")
    try {
        println("value:" + observe(target.buffered()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-e6692e8ba9801df3:0")
}

// Ledger klib-e73c2ae9564dc892: function transferTo(sink: RawSink): Long
fun f01_klib_e73c2ae9564dc892(target: kotlinx.io.Buffer, api_arg_0: RawSink) {
    println("CALL:klib-e73c2ae9564dc892:0")
    try {
        println("value:" + observe(target.transferTo(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-e73c2ae9564dc892:0")
}

// Ledger klib-e872d95c8706832c: function peek(): Source
fun f01_klib_e872d95c8706832c(target: kotlinx.io.Source) {
    println("CALL:klib-e872d95c8706832c:0")
    try {
        println("value:" + observe(target.peek()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-e872d95c8706832c:0")
}

// Ledger klib-e8a815654759b526: val size: Int
fun f01_klib_e8a815654759b526(target: kotlinx.io.bytestring.ByteString) {
    println("CALL:klib-e8a815654759b526:0")
    try {
        println("value:" + observe(target.size))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-e8a815654759b526:0")
}

// Ledger klib-ea2a6bf9a5d93882: function transferFrom(source: RawSource): Long
fun f01_klib_ea2a6bf9a5d93882(target: kotlinx.io.Buffer, api_arg_0: RawSource) {
    println("CALL:klib-ea2a6bf9a5d93882:0")
    try {
        println("value:" + observe(target.transferFrom(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ea2a6bf9a5d93882:0")
}

// Ledger klib-ea45816decad6959: function Sink.writeString(string: String, startIndex: Int = 0, endIndex: Int = string.length)
fun f01_klib_ea45816decad6959(target: Sink, api_arg_0: String, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-ea45816decad6959:0")
    try {
        println("value:" + observe(target.writeString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ea45816decad6959:0")
    println("CALL:klib-ea45816decad6959:1")
    try {
        println("value:" + observe(target.writeString(string = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ea45816decad6959:1")
}

// Ledger klib-eb2e0cdf209de26a: val SystemFileSystem: FileSystem
fun f01_klib_eb2e0cdf209de26a() {
    println("CALL:klib-eb2e0cdf209de26a:0")
    try {
        println("value:" + observe(kotlinx.io.files.SystemFileSystem))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-eb2e0cdf209de26a:0")
}

// Ledger klib-ec5be87f1757e6b8: function ByteString.isNotEmpty(): Boolean
fun f01_klib_ec5be87f1757e6b8(target: ByteString) {
    println("CALL:klib-ec5be87f1757e6b8:0")
    try {
        println("value:" + observe(target.isNotEmpty()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ec5be87f1757e6b8:0")
}

// Ledger klib-ee51a94316134963: val SystemTemporaryDirectory: Path
fun f01_klib_ee51a94316134963() {
    println("CALL:klib-ee51a94316134963:0")
    try {
        println("value:" + observe(kotlinx.io.files.SystemTemporaryDirectory))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ee51a94316134963:0")
}

// Ledger klib-ee5d9a571cd8e453: function append(byte: Byte)
fun f01_klib_ee5d9a571cd8e453(target: kotlinx.io.bytestring.ByteStringBuilder, api_arg_0: Byte) {
    println("CALL:klib-ee5d9a571cd8e453:0")
    try {
        println("value:" + observe(target.append(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ee5d9a571cd8e453:0")
}

// Ledger klib-f10f01d0ac1d5ee1: function readAtMostTo(sink: Buffer, byteCount: Long): Long
fun f01_klib_f10f01d0ac1d5ee1(target: kotlinx.io.Buffer, api_arg_0: Buffer, api_arg_1: Long) {
    println("CALL:klib-f10f01d0ac1d5ee1:0")
    try {
        println("value:" + observe(target.readAtMostTo(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f10f01d0ac1d5ee1:0")
}

// Ledger klib-f22691bc91e16f23: function readByte(): Byte
fun f01_klib_f22691bc91e16f23(target: kotlinx.io.Buffer) {
    println("CALL:klib-f22691bc91e16f23:0")
    try {
        println("value:" + observe(target.readByte()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f22691bc91e16f23:0")
}

// Ledger klib-f24361849bd7cfdd: function discardingSink(): RawSink
fun f01_klib_f24361849bd7cfdd() {
    println("CALL:klib-f24361849bd7cfdd:0")
    try {
        println("value:" + observe(discardingSink()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f24361849bd7cfdd:0")
}

// Ledger klib-f2a10f7f196b05da: function writeByte(byte: Byte)
fun f01_klib_f2a10f7f196b05da(target: kotlinx.io.Buffer, api_arg_0: Byte) {
    println("CALL:klib-f2a10f7f196b05da:0")
    try {
        println("value:" + observe(target.writeByte(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f2a10f7f196b05da:0")
}

// Ledger klib-f570c311693d6703: function setUnchecked(segment: Segment, offset: Int, b0: Byte, b1: Byte, b2: Byte)
fun f01_klib_f570c311693d6703(target: kotlinx.io.unsafe.SegmentWriteContext, api_arg_0: Segment, api_arg_1: Int, api_arg_2: Byte, api_arg_3: Byte, api_arg_4: Byte) {
    println("CALL:klib-f570c311693d6703:0")
    try {
        println("value:" + observe(target.setUnchecked(api_arg_0, api_arg_1, api_arg_2, api_arg_3, api_arg_4)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f570c311693d6703:0")
}

// Ledger klib-f6856a243e61dd47: function Base64.decodeToByteString(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteString
fun f01_klib_f6856a243e61dd47(api_arg_0: ByteString, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-f6856a243e61dd47:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f6856a243e61dd47:0")
    println("CALL:klib-f6856a243e61dd47:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decodeToByteString(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f6856a243e61dd47:1")
}

// Ledger klib-f69256afeaa9b7ce: function readShort(): Short
fun f01_klib_f69256afeaa9b7ce(target: kotlinx.io.Source) {
    println("CALL:klib-f69256afeaa9b7ce:0")
    try {
        println("value:" + observe(target.readShort()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f69256afeaa9b7ce:0")
}

// Ledger klib-f6cdd7b8ec302161: object UnsafeByteStringOperations
fun f01_klib_f6cdd7b8ec302161() {
    println("CALL:klib-f6cdd7b8ec302161:0")
    try {
        println("value:" + observe(kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f6cdd7b8ec302161:0")
}

// Ledger klib-f6fe9eab2b16817b: interface SegmentReadContext
fun f01_klib_f6fe9eab2b16817b(value: kotlinx.io.unsafe.SegmentReadContext) {
    println("CALL:klib-f6fe9eab2b16817b:0")
    try {
        println("value:" + observe(value))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f6fe9eab2b16817b:0")
}

// Ledger klib-f721a4a5df2ae655: function createDirectories(path: Path, mustCreate: Boolean = false)
fun f01_klib_f721a4a5df2ae655(target: kotlinx.io.files.FileSystem, api_arg_0: Path, api_arg_1: Boolean) {
    println("CALL:klib-f721a4a5df2ae655:0")
    try {
        println("value:" + observe(target.createDirectories(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f721a4a5df2ae655:0")
    println("CALL:klib-f721a4a5df2ae655:1")
    try {
        println("value:" + observe(target.createDirectories(path = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f721a4a5df2ae655:1")
}

// Ledger klib-f7b67ed1f0fd800e: function write(source: RawSource, byteCount: Long)
fun f01_klib_f7b67ed1f0fd800e(target: kotlinx.io.Buffer, api_arg_0: RawSource, api_arg_1: Long) {
    println("CALL:klib-f7b67ed1f0fd800e:0")
    try {
        println("value:" + observe(target.write(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f7b67ed1f0fd800e:0")
}

// Ledger klib-f7d98255f9d6ecdd: function Base64.decode(source: ByteString, startIndex: Int = 0, endIndex: Int = source.size): ByteArray
fun f01_klib_f7d98255f9d6ecdd(api_arg_0: ByteString, api_arg_1: Int, api_arg_2: Int) {
    println("CALL:klib-f7d98255f9d6ecdd:0")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decode(api_arg_0, api_arg_1, api_arg_2)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f7d98255f9d6ecdd:0")
    println("CALL:klib-f7d98255f9d6ecdd:1")
    try {
        println("value:" + observe(kotlin.io.encoding.Base64.decode(source = api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f7d98255f9d6ecdd:1")
}

// Ledger klib-f7ee387f61c6a2c0: function exhausted(): Boolean
fun f01_klib_f7ee387f61c6a2c0(target: kotlinx.io.Buffer) {
    println("CALL:klib-f7ee387f61c6a2c0:0")
    try {
        println("value:" + observe(target.exhausted()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-f7ee387f61c6a2c0:0")
}

// Ledger klib-fa07a4bb610a4de9: function transferFrom(source: RawSource): Long
fun f01_klib_fa07a4bb610a4de9(target: kotlinx.io.Sink, api_arg_0: RawSource) {
    println("CALL:klib-fa07a4bb610a4de9:0")
    try {
        println("value:" + observe(target.transferFrom(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fa07a4bb610a4de9:0")
}

// Ledger klib-fb2aeb01e083e94f: function Source.readUShortLe(): UShort
fun f01_klib_fb2aeb01e083e94f(target: Source) {
    println("CALL:klib-fb2aeb01e083e94f:0")
    try {
        println("value:" + observe(target.readUShortLe()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fb2aeb01e083e94f:0")
}

// Ledger klib-fbc3f88c6499a334: function ByteString.endsWith(byteString: ByteString): Boolean
fun f01_klib_fbc3f88c6499a334(target: ByteString, api_arg_0: ByteString) {
    println("CALL:klib-fbc3f88c6499a334:0")
    try {
        println("value:" + observe(target.endsWith(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fbc3f88c6499a334:0")
}

// Ledger klib-fbfc8c4cffccfd8f: function Source.readFloat(): Float
fun f01_klib_fbfc8c4cffccfd8f(target: Source) {
    println("CALL:klib-fbfc8c4cffccfd8f:0")
    try {
        println("value:" + observe(target.readFloat()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fbfc8c4cffccfd8f:0")
}

// Ledger klib-fc00249c9b381346: function Source.readDouble(): Double
fun f01_klib_fc00249c9b381346(target: Source) {
    println("CALL:klib-fc00249c9b381346:0")
    try {
        println("value:" + observe(target.readDouble()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fc00249c9b381346:0")
}

// Ledger klib-fc72f439d7d51eff: function Sink.writeULong(long: ULong)
fun f01_klib_fc72f439d7d51eff(target: Sink, api_arg_0: ULong) {
    println("CALL:klib-fc72f439d7d51eff:0")
    try {
        println("value:" + observe(target.writeULong(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fc72f439d7d51eff:0")
}

// Ledger klib-fcb3ae8472b429f2: function readAtMostTo(sink: Buffer, byteCount: Long): Long
fun f01_klib_fcb3ae8472b429f2(target: kotlinx.io.RawSource, api_arg_0: Buffer, api_arg_1: Long) {
    println("CALL:klib-fcb3ae8472b429f2:0")
    try {
        println("value:" + observe(target.readAtMostTo(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fcb3ae8472b429f2:0")
}

// Ledger klib-fcda5736a2a538fa: function atomicMove(source: Path, destination: Path)
fun f01_klib_fcda5736a2a538fa(target: kotlinx.io.files.FileSystem, api_arg_0: Path, api_arg_1: Path) {
    println("CALL:klib-fcda5736a2a538fa:0")
    try {
        println("value:" + observe(target.atomicMove(api_arg_0, api_arg_1)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fcda5736a2a538fa:0")
}

// Ledger klib-fcdd0c8f02bff324: function metadataOrNull(path: Path): FileMetadata?
fun f01_klib_fcdd0c8f02bff324(target: kotlinx.io.files.FileSystem, api_arg_0: Path) {
    println("CALL:klib-fcdd0c8f02bff324:0")
    try {
        println("value:" + observe(target.metadataOrNull(api_arg_0)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fcdd0c8f02bff324:0")
}

// Ledger klib-fdb3da4587313f8c: function setUnchecked(segment: Segment, offset: Int, b0: Byte, b1: Byte)
fun f01_klib_fdb3da4587313f8c(target: kotlinx.io.unsafe.SegmentWriteContext, api_arg_0: Segment, api_arg_1: Int, api_arg_2: Byte, api_arg_3: Byte) {
    println("CALL:klib-fdb3da4587313f8c:0")
    try {
        println("value:" + observe(target.setUnchecked(api_arg_0, api_arg_1, api_arg_2, api_arg_3)))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-fdb3da4587313f8c:0")
}

// Ledger klib-ff236788f8f69617: function Source.readLine(): String?
fun f01_klib_ff236788f8f69617(target: Source) {
    println("CALL:klib-ff236788f8f69617:0")
    try {
        println("value:" + observe(target.readLine()))
    } catch (failure: Throwable) {
        println("call-exception:" + exceptionType(failure))
    }
    println("CALL-END:klib-ff236788f8f69617:0")
}
