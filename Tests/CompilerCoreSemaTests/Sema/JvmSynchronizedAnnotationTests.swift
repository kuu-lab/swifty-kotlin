@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct JvmSynchronizedAnnotationTests {
    @Test(arguments: [false, true])
    func functionAndAccessorTargetsResolve(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifactPath = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        try withTemporaryFile(contents: """
        class Counter {
            var first = 0
                @Synchronized get
            var second = 0
                @Synchronized set
            @Synchronized fun method() = 1
            @get:Synchronized var third = 0
            @set:Synchronized var fourth = 0
        }
        @Synchronized fun topLevel() = 2
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], stdlibLibraryPath: artifactPath, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func classTargetRemainsInvalid() throws {
        try withTemporaryFile(contents: "@Synchronized class NotAValidTarget") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
        }
    }
}
