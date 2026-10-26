@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct IODeferredValCaptureTests {
    @Test
    func ordinaryDeferredValStillUsesBranchAssignments() throws {
        try withTemporaryFile(contents: """
        fun choose(flag: Boolean): Int {
            val result: Int
            if (flag) result = 1 else result = 2
            return result
        }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let module = try #require(ctx.kir)
            let failures = KIRVerifier.verify(module: module, symbols: ctx.sema?.symbols, interner: ctx.interner)
            #expect(failures.isEmpty)
        }
    }

    @Test
    func seedDoesNotAuthorizeReadsWithoutDefiniteAssignment() throws {
        let kinds = ["UNKNOWN", "AT_MOST_ONCE", "EXACTLY_ONCE"]
        let sources = kinds.enumerated().map { index, kind in
            """
            package refused\(index)
            import kotlin.contracts.*
            @OptIn(ExperimentalContracts::class)
            inline fun invoke(block: () -> Unit) {
                contract { callsInPlace(block, InvocationKind.\(kind)) }
                block()
            }
            fun bad(): Int {
                val value: Int
                invoke { \(kind == "EXACTLY_ONCE" ? "val before = value; " : "")value = 1 }
                return value
            }
            """
        }
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath)
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(
                inputs: paths, stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)
            for path in paths {
                #expect(diagnosticsForPath(path, in: ctx).contains { $0.code == "KSWIFTK-SEMA-0031" })
            }
        }
    }

    @Test(arguments: [false, true])
    func inPlaceCallbacksCaptureDefinedPrimitiveReferenceAndNestedCells(useLibrary: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { root.deleteLastPathComponent() }
        let source = root.appendingPathComponent("Scripts/diff_cases/kotlinx_io_unsafe_deferred_val_capture.kt")
        let library: String?
        if useLibrary {
            TestStdlibCache.shared.prepare()
            library = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            library = nil
        }
        let ctx = makeCompilationContext(
            inputs: [source.path], stdlibLibraryPath: library, allowDefaultStdlibLibrary: false
        )
        #expect(ctx.options.includeStdlib == !useLibrary)
        try runToLowering(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let module = try #require(ctx.kir)
        let failures = KIRVerifier.verify(module: module, symbols: ctx.sema?.symbols, interner: ctx.interner)
        #expect(failures.isEmpty, "\(failures)")
    }
}
