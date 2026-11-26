#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kuu4717PrimitiveCompanionFromBitsBuildAndRun() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let consumer = """
            fun companionWithEffect(): Float.Companion {
                println("receiver")
                return Float.Companion
            }
            fun Float.Companion.convert(bits: Int): Float = fromBits(bits)
            fun main() {
                println(Float.fromBits(1069547520))
                println(Float.Companion.fromBits(bits = 1069547520))
                println(Double.fromBits(4609434218613702656L))
                println(Double.Companion.fromBits(bits = 4609434218613702656L))
                println(companionWithEffect().fromBits(2))
                println(Float.convert(3))
                println(Float.fromBits(bits = 0x7FC00123).toRawBits())
                println(Double.fromBits(bits = 0x7FF8000000000123L).toRawBits())
            }
            """
            let app = try m22Build(root: root, sources: [("consumer.kt", consumer)], name: "app.jar", mode: .jvmJar)
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let run = try java(["-cp", app.0.path + ":" + library.path, "ConsumerKt"])
            #expect(run.stdout == "1.5\n1.5\n1.5\n1.5\nreceiver\n2.8E-45\n4.2E-45\n2143289635\n9221120237041090851\n")
            #expect(run.stderr.isEmpty)
        }
    }
}
#endif
