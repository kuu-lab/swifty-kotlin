@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct JvmStaticAccessorAnnotationTests {
    @Test(arguments: [false, true])
    func accessorTargetsAreAvailable(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifactPath = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        try withTemporaryFile(contents: """
        object C {
            var first = 0
                @JvmStatic get
            var second = 0
                @JvmStatic set
            @JvmStatic var third = 0
            @JvmStatic fun method() = 1
        }
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
        try withTemporaryFile(contents: "@JvmStatic class NotAValidTarget") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ANNOTATION-TARGET" })
        }
    }
}
