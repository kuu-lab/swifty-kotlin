#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibDiagnosticsTests {
    /// Bundled stdlib sources must not produce any diagnostics, including warnings.
    /// A minimal user file is required because LoadSourcesPhase rejects empty inputs.
    @Test
    func testBundledStdlibEmitsZeroDiagnostics() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let bundledDiagnostics = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return !isUserSourceRange(range, in: ctx)
            }

            let bundledErrors = bundledDiagnostics.filter { $0.severity == .error }
            let bundledWarnings = bundledDiagnostics.filter { $0.severity == .warning }
            let bundledNotes = bundledDiagnostics.filter { $0.severity == .note }
            let bundledInfo = bundledDiagnostics.filter { $0.severity == .info }

            #expect(
                bundledErrors.isEmpty,
                "Bundled stdlib produced errors: \(bundledErrors)"
            )
            #expect(
                bundledWarnings.isEmpty,
                "Bundled stdlib produced warnings: \(bundledWarnings)"
            )
            #expect(
                bundledNotes.isEmpty,
                "Bundled stdlib produced notes: \(bundledNotes)"
            )
            #expect(
                bundledInfo.isEmpty,
                "Bundled stdlib produced info diagnostics: \(bundledInfo)"
            )
        }
    }

    /// A minimal user file still typechecks bundled Result sources but must not expose their unchecked-cast warnings.
    @Test
    func testBundledResultUncheckedCastWarningsDoNotHideUserWarnings() throws {
        let source = """
        fun cast(value: Any): List<Int> = value as List<Int>
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let uncheckedCastWarnings = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-UNCHECKED-CAST" && $0.severity == .warning
            }
            let userWarnings = uncheckedCastWarnings.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return isUserSourceRange(range, in: ctx)
            }
            let bundledWarnings = uncheckedCastWarnings.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return !isUserSourceRange(range, in: ctx)
            }

            #expect(userWarnings.count == 1, "Expected the user cast warning to remain visible: \(uncheckedCastWarnings)")
            #expect(bundledWarnings.isEmpty, "Bundled Result cast warnings leaked: \(bundledWarnings)")
        }
    }

    @Test
    func testStdlibSuppressionsDoNotHideUserWarnings() throws {
        let source = """
        import kotlinx.coroutines.test.StandardTestDispatcher

        fun unchecked(value: Any): List<String> = value as List<String>
        fun experimental() { StandardTestDispatcher() }
        fun unreachable(): Int {
            return 1
            return 2
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected errors: \(ctx.diagnostics.diagnostics)")
            let userWarnings = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return diagnostic.severity == .warning && isUserSourceRange(range, in: ctx)
            }
            #expect(userWarnings.map(\.code).sorted() == [
                "KSWIFTK-SEMA-0096",
                "KSWIFTK-SEMA-OPT-IN",
                "KSWIFTK-SEMA-UNCHECKED-CAST"
            ])
            let bundledDiagnostics = ctx.diagnostics.diagnostics.filter { diagnostic in
                guard let range = diagnostic.primaryRange else { return false }
                return !isUserSourceRange(range, in: ctx)
            }
            #expect(bundledDiagnostics.isEmpty, "Unexpected stdlib diagnostics: \(bundledDiagnostics)")
        }
    }

    /// Deprecated ERROR-level compatibility stubs in the bundled
    /// kotlinx.coroutines.flow sources must reject call sites with
    /// KSWIFTK-SEMA-DEPRECATED, matching kotlinc's behavior for the same APIs.
    @Test
    func testDeprecatedFlowStubsEmitErrorDiagnostics() throws {
        let source = """
        import kotlinx.coroutines.flow.*

        fun main() = kotlinx.coroutines.runBlocking {
            val outer = flowOf(flowOf(1))
            outer.merge()
            outer.flatten()
            flowOf(1, 2, 3).scanReduce { a, b -> a + b }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let deprecatedErrors = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-DEPRECATED" && $0.severity == .error
            }
            #expect(
                deprecatedErrors.count == 3,
                "Expected 3 deprecation errors for merge/flatten/scanReduce stubs: \(ctx.diagnostics.diagnostics)"
            )
        }
    }

    /// KUU-1393: `scanReduce` is not a Kotlin stdlib API — it was renamed to
    /// `runningReduce` in Kotlin 1.5 and does not exist on any receiver in
    /// Kotlin 2.3.10. Every receiver must reject it as unresolved, matching
    /// kotlinc's `unresolved reference 'scanReduce'`.
    @Test
    func testScanReduceRejectedOnAllReceivers() throws {
        let receivers: [(label: String, call: String)] = [
            ("List", "listOf(1, 2).scanReduce { a, b -> a + b }"),
            ("MutableList", "mutableListOf(1, 2).scanReduce { a, b -> a + b }"),
            ("Set", "setOf(1, 2).scanReduce { a, b -> a + b }"),
            ("Iterable", "xs.scanReduce { a, b -> a + b }"),
            ("Sequence", "sequenceOf(1, 2).scanReduce { a, b -> a + b }"),
            ("Array", "arrayOf(1, 2).scanReduce { a, b -> a + b }"),
            ("IntArray", "intArrayOf(1, 2).scanReduce { a, b -> a + b }"),
            ("CharArray", "charArrayOf('a', 'b').scanReduce { a, b -> a }"),
            ("CharSequence", "cs.scanReduce { a, b -> a }"),
            ("String", "\"ab\".scanReduce { a, b -> a }"),
        ]
        for (label, call) in receivers {
            let prelude = switch label {
            case "Iterable": "val xs: Iterable<Int> = listOf(1, 2)\n"
            case "CharSequence": "val cs: CharSequence = \"ab\"\n"
            default: ""
            }
            let source = """
            \(prelude)fun main() {
                println(\(call))
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                #expect(
                    ctx.diagnostics.hasError,
                    "\(label).scanReduce must be unresolved like kotlinc: \(ctx.diagnostics.diagnostics.map(\.code))"
                )
            }
        }
    }
}
#endif
