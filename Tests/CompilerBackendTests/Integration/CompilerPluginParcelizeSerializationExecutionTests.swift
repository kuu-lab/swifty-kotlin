@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite(.serialized)
struct CompilerPluginParcelizeSerializationExecutionTests {

    @Test
    func parcelizeAndSerializationBodiesExecuteAtRuntime() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let parcelStubs = """
        package android.os

        interface Parcelable {
            interface Creator<T> {
                fun createFromParcel(parcel: Parcel): T
                fun newArray(size: Int): Array<T?>
            }
        }

        class Parcel {
            private val ints = mutableListOf<Int>()
            private val strings = mutableListOf<String>()
            private var intIdx = 0
            private var strIdx = 0

            fun writeInt(v: Int) { ints.add(v) }
            fun writeString(v: String) { strings.add(v) }
            fun readInt(): Int = ints[intIdx++]
            fun readString(): String = strings[strIdx++]
        }
        """

        let parcelizeAnnotations = """
        package kotlinx.parcelize

        annotation class Parcelize
        annotation class IgnoredOnParcel
        """

        let mainSource = """
        package com.example

        import android.os.Parcel
        import android.os.Parcelable
        import kotlinx.parcelize.IgnoredOnParcel
        import kotlinx.parcelize.Parcelize
        import kotlinx.serialization.SerialName
        import kotlinx.serialization.Serializable
        import kotlinx.serialization.descriptors.SerialDescriptor
        import kotlinx.serialization.encoding.CompositeDecoder
        import kotlinx.serialization.encoding.CompositeEncoder
        import kotlinx.serialization.encoding.Decoder
        import kotlinx.serialization.encoding.Encoder
        import kotlinx.serialization.modules.EmptySerializersModule
        import kotlinx.serialization.modules.SerializersModule

        @Parcelize
        class ParcelItem(val title: String, val count: Int) : Parcelable {
            @IgnoredOnParcel
            val transientNote: Int = 99
        }

        @Serializable
        class Record(
            @SerialName("record_name")
            val name: String,
            val score: Int
        )

        class BufferStorage {
            val strs = mutableListOf<String>()
            val ints = mutableListOf<Int>()
        }

        class BufferEncoder(private val storage: BufferStorage) : Encoder, CompositeEncoder {
            override val serializersModule: SerializersModule = EmptySerializersModule()

            override fun beginStructure(descriptor: SerialDescriptor): CompositeEncoder = this
            override fun endStructure(descriptor: SerialDescriptor) {}

            override fun encodeStringElement(descriptor: SerialDescriptor, index: Int, value: String) {
                storage.strs.add(descriptor.getElementName(index) + "=" + value)
            }
            override fun encodeIntElement(descriptor: SerialDescriptor, index: Int, value: Int) {
                storage.ints.add(value)
            }

            override fun encodeNull() {}
            override fun encodeBoolean(value: Boolean) {}
            override fun encodeByte(value: Byte) {}
            override fun encodeShort(value: Short) {}
            override fun encodeChar(value: Char) {}
            override fun encodeInt(value: Int) {}
            override fun encodeLong(value: Long) {}
            override fun encodeFloat(value: Float) {}
            override fun encodeDouble(value: Double) {}
            override fun encodeString(value: String) {}
            override fun encodeEnum(enumDescriptor: SerialDescriptor, index: Int) {}
            override fun encodeInline(descriptor: SerialDescriptor): Encoder = this

            override fun encodeBooleanElement(descriptor: SerialDescriptor, index: Int, value: Boolean) {}
            override fun encodeByteElement(descriptor: SerialDescriptor, index: Int, value: Byte) {}
            override fun encodeShortElement(descriptor: SerialDescriptor, index: Int, value: Short) {}
            override fun encodeCharElement(descriptor: SerialDescriptor, index: Int, value: Char) {}
            override fun encodeLongElement(descriptor: SerialDescriptor, index: Int, value: Long) {}
            override fun encodeFloatElement(descriptor: SerialDescriptor, index: Int, value: Float) {}
            override fun encodeDoubleElement(descriptor: SerialDescriptor, index: Int, value: Double) {}
            override fun <T> encodeSerializableElement(descriptor: SerialDescriptor, index: Int, serializer: kotlinx.serialization.SerializationStrategy<T>, value: T) {}
            override fun <T : Any> encodeNullableSerializableElement(descriptor: SerialDescriptor, index: Int, serializer: kotlinx.serialization.SerializationStrategy<T>, value: T?) {}
            override fun encodeInlineElement(descriptor: SerialDescriptor, index: Int): Encoder = this
        }

        class BufferDecoder(private val storage: BufferStorage) : Decoder, CompositeDecoder {
            override val serializersModule: SerializersModule = EmptySerializersModule()
            private var decodeIdx = 0

            override fun beginStructure(descriptor: SerialDescriptor): CompositeDecoder {
                decodeIdx = 0
                return this
            }
            override fun endStructure(descriptor: SerialDescriptor) {}

            override fun decodeElementIndex(descriptor: SerialDescriptor): Int {
                if (decodeIdx >= descriptor.elementsCount) return CompositeDecoder.DECODE_DONE
                val cur = decodeIdx
                decodeIdx++
                return cur
            }
            override fun decodeStringElement(descriptor: SerialDescriptor, index: Int): String = "Bob"
            override fun decodeIntElement(descriptor: SerialDescriptor, index: Int): Int = storage.ints[0] + 5

            override fun decodeNotNullMark(): Boolean = true
            override fun decodeNull(): Nothing? = null
            override fun decodeBoolean(): Boolean = false
            override fun decodeByte(): Byte = 0
            override fun decodeShort(): Short = 0
            override fun decodeChar(): Char = 'a'
            override fun decodeInt(): Int = 0
            override fun decodeLong(): Long = 0L
            override fun decodeFloat(): Float = 0f
            override fun decodeDouble(): Double = 0.0
            override fun decodeString(): String = ""
            override fun decodeEnum(enumDescriptor: SerialDescriptor): Int = 0
            override fun decodeInline(descriptor: SerialDescriptor): Decoder = this

            override fun decodeBooleanElement(descriptor: SerialDescriptor, index: Int): Boolean = false
            override fun decodeByteElement(descriptor: SerialDescriptor, index: Int): Byte = 0
            override fun decodeCharElement(descriptor: SerialDescriptor, index: Int): Char = 'a'
            override fun decodeShortElement(descriptor: SerialDescriptor, index: Int): Short = 0
            override fun decodeLongElement(descriptor: SerialDescriptor, index: Int): Long = 0L
            override fun decodeFloatElement(descriptor: SerialDescriptor, index: Int): Float = 0f
            override fun decodeDoubleElement(descriptor: SerialDescriptor, index: Int): Double = 0.0
            override fun <T> decodeSerializableElement(descriptor: SerialDescriptor, index: Int, deserializer: kotlinx.serialization.DeserializationStrategy<T>, previousValue: T?): T {
                @Suppress("UNCHECKED_CAST")
                return null as T
            }
            override fun <T : Any> decodeNullableSerializableElement(descriptor: SerialDescriptor, index: Int, deserializer: kotlinx.serialization.DeserializationStrategy<T?>, previousValue: T?): T? = null
            override fun decodeInlineElement(descriptor: SerialDescriptor, index: Int): Decoder = this
        }

        fun main() {
            val parcel = Parcel()
            val item = ParcelItem("Book", 42)
            item.writeToParcel(parcel, 0)
            val restored = ParcelItem.CREATOR.createFromParcel(parcel)
            println(restored.title)
            println(restored.count)

            val ser = Record.serializer()
            println(ser.descriptor.serialName)
            println(ser.descriptor.elementsCount)
            println(ser.descriptor.getElementName(0))
            println(ser.descriptor.getElementName(1))

            val storage = BufferStorage()
            val encoder = BufferEncoder(storage)
            ser.serialize(encoder, Record("Alice", 10))
            println(storage.strs[0])
            val decoder = BufferDecoder(storage)
            val decoded = ser.deserialize(decoder)
            println(decoded.name)
            println(decoded.score)
        }
        """

        let pPath = directory.appendingPathComponent("parcel_stubs.kt").path
        let annPath = directory.appendingPathComponent("parcelize_ann.kt").path
        let mainPath = directory.appendingPathComponent("main.kt").path
        let outputPath = directory.appendingPathComponent("parcel_ser_exec_out").path
        try parcelStubs.write(toFile: pPath, atomically: true, encoding: .utf8)
        try parcelizeAnnotations.write(toFile: annPath, atomically: true, encoding: .utf8)
        try mainSource.write(toFile: mainPath, atomically: true, encoding: .utf8)

        let options = CompilerOptions(
            moduleName: "ParcelSerExec",
            inputs: [pPath, annPath, mainPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple(),
            optLevel: .O0,
            includeStdlib: false,
            stdlibLibraryPath: try testStdlibArtifactPath(),
            allowDefaultStdlibLibrary: true
        )
        try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

        let result = try CommandRunner.run(executable: outputPath, arguments: [])
        #expect(result.exitCode == 0, "\(result.stderr)")
        let expected = [
            "Book",
            "42",
            "com.example.Record",
            "2",
            "record_name",
            "score",
            "record_name=Alice",
            "Bob",
            "15",
        ].joined(separator: "\n") + "\n"
        #expect(result.stdout == expected)
    }
}
