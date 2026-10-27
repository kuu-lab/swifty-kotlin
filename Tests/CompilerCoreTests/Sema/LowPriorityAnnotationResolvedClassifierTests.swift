@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct LowPriorityAnnotationResolvedClassifierTests {
    @Test(arguments: [false, true])
    func suppressedInternalAnnotationResolvesAtEachDeclaration(useArtifact: Bool) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        try withTemporaryFile(contents: """
        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @kotlin.internal.LowPriorityInOverloadResolution
        fun choose(value: Int) = "low"
        fun choose(value: Any) = "normal"

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @kotlin.internal.LowPriorityInOverloadResolution
        val property = 1

        class Example @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @kotlin.internal.LowPriorityInOverloadResolution constructor(value: String) {
            @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
            @kotlin.internal.LowPriorityInOverloadResolution
            constructor(value: Int) : this(value.toString())
        }
        """) { path in
            let ctx = makeCompilationContext(
                inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [false, true], [
        """
        @kotlin.internal.LowPriorityInOverloadResolution
        fun invalid() {}
        """,
        """
        class Example @kotlin.internal.LowPriorityInOverloadResolution constructor()
        """,
        """
        class Example {
            @kotlin.internal.LowPriorityInOverloadResolution constructor()
        }
        """,
        """
        @Deprecated("no", level = DeprecationLevel.ERROR)
        @Retention(AnnotationRetention.BINARY)
        annotation class Bad
        @Bad fun invalid() {}
        """,
        """
        @RequiresOptIn(level = RequiresOptIn.Level.ERROR)
        annotation class ExperimentalFlag
        @ExperimentalFlag @Retention(AnnotationRetention.BINARY)
        annotation class Mark
        @Mark fun invalid() {}
        """,
        """
        annotation class Required(val value: Int)
        @Required fun invalid() {}
        """,
    ])
    func rejectsInvalidAnnotations(useArtifact: Bool, source: String) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected rejection: \(source)")
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.allSatisfy { !$0.message.contains("$annotationResolved") }, "\(errors)")
            if source.contains("kotlin.internal.LowPriorityInOverloadResolution") {
                #expect(errors.contains {
                    $0.code == "KSWIFTK-SEMA-0044"
                        && $0.message.contains("kotlin.internal.LowPriorityInOverloadResolution")
                }, "\(errors)")
            }
        }
    }
}
