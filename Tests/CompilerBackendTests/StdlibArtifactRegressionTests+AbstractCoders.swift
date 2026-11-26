@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    @Test
    func testAbstractEncoderAndDecoderSkeletonsThroughStdlibArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let source = """
        import kotlinx.serialization.*
        import kotlinx.serialization.descriptors.*
        import kotlinx.serialization.encoding.*
        import kotlinx.serialization.modules.*

        data class Point(val x: Int, val label: String)

        object PointSerializer : KSerializer<Point> {
            override val descriptor: SerialDescriptor = buildClassSerialDescriptor("Point") {
                element("x", PrimitiveSerialDescriptor("x", PrimitiveKind.INT))
                element("label", PrimitiveSerialDescriptor("label", PrimitiveKind.STRING))
            }

            override fun serialize(encoder: Encoder, value: Point) {
                val composite = encoder.beginStructure(descriptor)
                composite.encodeIntElement(descriptor, 0, value.x)
                composite.encodeStringElement(descriptor, 1, value.label)
                composite.endStructure(descriptor)
            }

            override fun deserialize(decoder: Decoder): Point {
                val composite = decoder.beginStructure(descriptor)
                val x = composite.decodeIntElement(descriptor, 0)
                val label = composite.decodeStringElement(descriptor, 1)
                composite.endStructure(descriptor)
                return Point(x, label)
            }
        }

        @OptIn(ExperimentalSerializationApi::class)
        class RecordingEncoder : AbstractEncoder() {
            override val serializersModule: SerializersModule = EmptySerializersModule()
            val values = mutableListOf<Any>()

            override fun encodeElement(descriptor: SerialDescriptor, index: Int): Boolean {
                values.add(descriptor.getElementName(index))
                return index == 0 || values.size < 10
            }

            override fun encodeValue(value: Any) {
                values.add(value)
            }
        }

        @OptIn(ExperimentalSerializationApi::class)
        class QueueDecoder(private val queue: ArrayDeque<Any>) : AbstractDecoder() {
            override val serializersModule: SerializersModule = EmptySerializersModule()

            override fun decodeValue(): Any = queue.removeFirst()

            override fun decodeElementIndex(descriptor: SerialDescriptor): Int = CompositeDecoder.DECODE_DONE
        }

        @OptIn(ExperimentalSerializationApi::class)
        fun main() {
            val encoder = RecordingEncoder()
            encoder.encodeSerializableValue(PointSerializer, Point(7, "seven"))
            println(encoder.values)
            val decoder = QueueDecoder(ArrayDeque(listOf<Any>(3, "three")))
            println(PointSerializer.deserialize(decoder))
            try {
                RecordingEncoder().encodeNull()
            } catch (e: SerializationException) {
                println("null: ${e.message}")
            }
        }
        """
        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "AbstractCoders",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == """
            [x, 7, label, seven]
            Point(x=3, label=three)
            null: 'null' is not supported by default

            """)
        }
    }
}
