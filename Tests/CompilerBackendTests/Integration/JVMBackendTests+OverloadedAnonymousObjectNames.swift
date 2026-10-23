#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func overloadedExtensionAnonymousObjectsHaveDistinctNames() throws {
        try withWorkspace { root in
            let source = """
            class OverloadedObjectReceiver
            interface OverloadedObjectValue { fun result(): Int }

            fun OverloadedObjectReceiver.transform(seed: Int, transform: (Int) -> Int): OverloadedObjectValue =
                object : OverloadedObjectValue {
                    override fun result(): Int = transform(seed)
                }

            fun OverloadedObjectReceiver.transform(seed: String, transform: (String) -> Int): OverloadedObjectValue =
                object : OverloadedObjectValue {
                    override fun result(): Int = transform(seed)
                }

            fun main() {
                val receiver = OverloadedObjectReceiver()
                println(receiver.transform(3) { it + 4 }.result())
                println(receiver.transform("abc") { it.length }.result())
            }
            """
            let app = try m22Build(
                root: root,
                sources: [("Main.kt", source)],
                name: "app.jar"
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let runtime = try m11Runtime()
            let candidate = try java(["-cp", app.0.path + ":" + runtime, "MainKt"])
            #expect(candidate.stderr.isEmpty)
            #expect(candidate.stdout == "7\n3\n")
        }
    }
}
#endif
