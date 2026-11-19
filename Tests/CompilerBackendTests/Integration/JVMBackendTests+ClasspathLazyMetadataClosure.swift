#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func lazyMemberFunctionMetadataTypesJoinTheClosure() throws {
        try withWorkspace { root in
            try """
            package dep

            class InputMerger

            class WorkRequest {
                class Builder {
                    fun setInputMerger(inputMerger: Class<out InputMerger>): Builder = this
                }
            }
            """.write(to: root.appendingPathComponent("Work.kt"), atomically: true, encoding: .utf8)
            _ = try jvmTool("kotlinc", ["Work.kt", "-d", "work.jar"], root: root)
            let work = root.appendingPathComponent("work.jar")
            let index = try JVMClasspathIndex.load(
                [work.path], automaticLazyClasspathMemberLimit: 1
            )

            let consumerPath = root.appendingPathComponent("consumer.kt").path
            let ctx = CompilationContext(
                options: CompilerOptions(
                    moduleName: "LazyMetadataTest",
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
            _ = ctx.sourceManager.addFile(path: consumerPath, contents: Data("""
            package consumer

            fun probe(builder: dep.WorkRequest.Builder) {
                println(builder)
            }
            """.utf8))
            try index.inject(into: ctx)

            // `Class<out InputMerger>` erases to `java.lang.Class` in the JVM
            // descriptor; only Kotlin metadata retains InputMerger.
            #expect(ctx.sourceManager.fileID(forPath: "<kswiftk-jvm-import>/dep/InputMerger.kt") != nil)
            let requestPath = "<kswiftk-jvm-import>/dep/WorkRequest.kt"
            let requestID = try #require(ctx.sourceManager.fileID(forPath: requestPath))
            let request = String(decoding: ctx.sourceManager.contents(of: requestID), as: UTF8.self)
            #expect(request.contains("setInputMerger"))
        }
    }
}
#endif
