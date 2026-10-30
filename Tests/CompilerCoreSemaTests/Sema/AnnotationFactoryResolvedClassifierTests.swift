@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct AnnotationFactoryResolvedClassifierTests {
    @Test(arguments: [false, true], ["BINARY", "RUNTIME"])
    func qualifiedPrivateAnnotationRespectsVisibilityAndSuppression(useArtifact: Bool, retention: String) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        let artifact = useArtifact ? try #require(CompilerOptions.defaultStdlibLibraryPath) : nil
        let definition = """
        package hidden
        @Retention(AnnotationRetention.\(retention))
        private annotation class Hidden
        """
        let usage = """
        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @hidden.Hidden fun allowed() {}
        @hidden.Hidden fun forbidden() {}
        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE") @hidden.Hidden val allowedProperty = 1
        @hidden.Hidden val forbiddenProperty = 2
        class Allowed @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE") @hidden.Hidden constructor(value: Int) {
            @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE") @hidden.Hidden constructor() : this(1)
        }
        class Forbidden @hidden.Hidden constructor(value: Int) {
            @hidden.Hidden constructor() : this(1)
        }
        """
        try withTemporaryFiles(contents: [definition, usage]) { paths in
            let ctx = makeCompilationContext(
                inputs: paths, stdlibLibraryPath: artifact, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            let usageFile = try #require(ctx.sourceManager.fileID(forPath: paths[1]))
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            let errorLines = errors.compactMap { diagnostic in
                diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
            }
            #expect(errors.count == 4, "\(errors)")
            #expect(Set(errorLines) == [3, 5, 9, 10], "\(errors)")
            #expect(errors.allSatisfy {
                $0.code == "KSWIFTK-SEMA-0040"
                    && $0.message.contains("hidden.Hidden")
                    && !$0.message.contains("$annotationResolved")
                    && $0.primaryRange?.start.file == usageFile
            }, "\(errors)")
        }
    }
}
