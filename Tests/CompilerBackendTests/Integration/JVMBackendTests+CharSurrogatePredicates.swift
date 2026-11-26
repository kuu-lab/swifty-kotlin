#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4665CharSurrogatePredicates(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                println('\\uD7FF'.isHighSurrogate())
                println('\\uD800'.isHighSurrogate())
                println('\\uDBFF'.isHighSurrogate())
                println('\\uDC00'.isHighSurrogate())
                println('\\uDBFF'.isLowSurrogate())
                println('\\uDC00'.isLowSurrogate())
                println('\\uDFFF'.isLowSurrogate())
                println('\\uE000'.isLowSurrogate())
            }
            """
            let expected = "false\ntrue\ntrue\nfalse\nfalse\ntrue\ntrue\nfalse\n"
            let app = try m22Build(root: root, sources: [("hello.kt", source)], name: mode == .jvmJar ? "app.jar" : "classes", mode: mode, classpath: [library.path])
            try #require(app.1 == 0, "\(app.2.map(\.message))")
            let candidate = try java(["-cp", app.0.path + ":" + library.path, "HelloKt"])
            #expect(candidate.stdout == expected)
            #expect(candidate.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + m11Runtime(), "HelloKt"])
            #expect(reference.stdout == expected)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
