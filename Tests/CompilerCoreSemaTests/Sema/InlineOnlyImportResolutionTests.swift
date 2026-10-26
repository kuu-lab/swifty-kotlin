#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct InlineOnlyImportResolutionTests {
    private func context(_ sources: [String], usePrecompiledStdlib: Bool) -> CompilationContext {
        if usePrecompiledStdlib {
            TestStdlibCache.shared.prepare()
        }
        let userPaths = sources.indices.map { index in
            FileManager.default.temporaryDirectory
                .appendingPathComponent("inline-only-user-\(index)-\(UUID().uuidString).kt").path
        }
        let ctx = makeCompilationContext(
            inputs: userPaths,
            moduleName: "InlineOnlyImportResolution",
            includeStdlib: usePrecompiledStdlib,
            allowDefaultStdlibLibrary: usePrecompiledStdlib
        )
        for (path, source) in zip(userPaths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }

        if !usePrecompiledStdlib {
            let internalAnnotationsPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("inline-only-stdlib-\(UUID().uuidString).kt").path
            _ = ctx.sourceManager.addFile(
                path: internalAnnotationsPath,
                contents: Data("""
                package kotlin.internal

                internal annotation class InlineOnly
                internal annotation class OnlyInputTypes
                """.utf8),
                origin: .bundledStdlib
            )

            let suppressAnnotationPath = FileManager.default.temporaryDirectory
                .appendingPathComponent("inline-only-suppress-annotation-\(UUID().uuidString).kt").path
            _ = ctx.sourceManager.addFile(
                path: suppressAnnotationPath,
                contents: Data("""
                package kotlin

                @kotlin.annotation.Target(kotlin.annotation.AnnotationTarget.FILE)
                annotation class Suppress(vararg val names: String)
                """.utf8),
                origin: .bundledStdlib
            )
        }
        return ctx
    }

    @Test(arguments: [false, true])
    func suppressedImportResolvesWhileUnannotatedImportRemainsInaccessible(usePrecompiledStdlib: Bool) throws {
        let ctx = context([
            """
            @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
            package repro

            import kotlin.internal.InlineOnly
            import kotlin.internal.OnlyInputTypes

            @InlineOnly
            public inline fun <@OnlyInputTypes T> identity(value: T): T = value

            public inline fun <T> ordinaryInline(value: T): T = value
            """,
            """
            package repro.unsuppressed

            import kotlin.internal.InlineOnly

            public inline fun <T> ordinaryInline(value: T): T = value
            """,
        ], usePrecompiledStdlib: usePrecompiledStdlib)

        try runSema(ctx)

        if usePrecompiledStdlib {
            #expect(ctx.options.stdlibLibraryPath != nil)
        }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0044" }, "\(ctx.diagnostics.diagnostics)")
        #expect(!ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
    }
}
#endif
