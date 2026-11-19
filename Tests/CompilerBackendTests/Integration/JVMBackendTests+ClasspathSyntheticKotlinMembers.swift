#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    private func externalReifiedCodecLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        interface Strategy<T>

        abstract class Codec {
            fun <T> encode(strategy: Strategy<T>, value: T): String = "two"
            inline fun <reified T> encode(value: T): String = "one"
            companion object Default : Codec()
        }
        """.write(to: root.appendingPathComponent("CodecLibrary.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["CodecLibrary.kt", "-d", "codec-library.jar"], root: root)
        return root.appendingPathComponent("codec-library.jar")
    }

    private func externalHiddenDeprecatedLibraryJar(_ root: URL) throws -> URL {
        try """
        package fixture

        @Deprecated("hidden", level = DeprecationLevel.HIDDEN)
        fun hidden(): Int = 1

        fun visible(): Int = 2
        """.write(to: root.appendingPathComponent("HiddenLibrary.kt"), atomically: true, encoding: .utf8)
        _ = try jvmTool("kotlinc", ["HiddenLibrary.kt", "-d", "hidden-library.jar"], root: root)
        return root.appendingPathComponent("hidden-library.jar")
    }

    @Test
    func externalKotlinSyntheticReifiedMemberResolvesBesideOverload() throws {
        try withWorkspace { root in
            let library = try externalReifiedCodecLibraryJar(root)
            let compiled = try compile("""
            import fixture.Codec
            fun main() {
                val map = mutableMapOf<String, String>()
                map["a"] = "b"
                println(Codec.encode(map))
            }
            """, root: root, mode: .jvmJar, classpath: [library.path])
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let execution = try java(["-cp", root.appendingPathComponent("hello.jar").path + ":" + library.path + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "one\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test
    func classpathHiddenDeprecatedSyntheticMemberStaysHidden() throws {
        try withWorkspace { root in
            let library = try externalHiddenDeprecatedLibraryJar(root)
            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "HiddenDeprecationTest",
                    inputs: [consumerPath],
                    outputPath: root.appendingPathComponent("out").path,
                    emit: .jvmJar,
                    target: .hostDefault(),
                    includeStdlib: false,
                    allowDefaultStdlibLibrary: false
                ),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("import fixture.visible\nfun main() { println(visible()) }".utf8))
            let index = try JVMClasspathIndex.load([library.path])
            try index.inject(into: ctx)

            let facadePath = "<kswiftk-jvm-import>/fixture/HiddenLibraryKt.kt"
            let facadeID = try #require(ctx.sourceManager.fileID(forPath: facadePath))
            let facade = String(decoding: ctx.sourceManager.contents(of: facadeID), as: UTF8.self)
            #expect(facade.contains("`visible`"))
            #expect(!facade.contains("`hidden`"))
        }
    }
}
#endif
