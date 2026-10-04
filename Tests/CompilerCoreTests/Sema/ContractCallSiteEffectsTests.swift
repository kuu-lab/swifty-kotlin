#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ContractCallSiteEffectsTests {
    private let declarations = """
    import kotlin.contracts.*
    @OptIn(ExperimentalContracts::class)
    fun present(x: String?): Boolean {
        contract { returns(true) implies (x != null) }
        return x != null
    }
    @OptIn(ExperimentalContracts::class)
    fun absent(x: String?): Boolean {
        contract { returns(false) implies (x != null) }
        return x == null
    }
    @OptIn(ExperimentalContracts::class)
    fun result(x: String?): String? {
        contract { returnsNotNull() implies (x != null) }
        return x
    }
    @OptIn(ExperimentalContracts::class)
    fun both(a: String?, b: String?): Boolean {
        contract {
            returns(true) implies (a != null)
            returns(true) implies (b != null)
        }
        return a != null && b != null
    }
    @OptIn(ExperimentalContracts::class)
    fun predicate(condition: Boolean): Boolean {
        contract { returns(true) implies condition }
        return condition
    }
    @OptIn(ExperimentalContracts::class)
    fun maybe(x: String?): Boolean? {
        contract { returns(true) implies (x != null) }
        return if (x != null) true else null
    }
    @OptIn(ExperimentalContracts::class)
    fun ensureBoth(a: String?, b: String?) {
        contract {
            returns() implies (a != null)
            returns() implies (b != null)
        }
        if (a == null || b == null) throw IllegalArgumentException()
    }
    """

    @Test
    func conditionalEffectsNarrowOnlyMatchingBranches() throws {
        let positive = [
            "if (present(x)) println(x.length)",
            "if (!absent(x)) println(x.length)",
            "if (absent(x)) {} else println(x.length)",
            "if (present(x) == true) println(x.length)",
            "if (false == absent(x)) println(x.length)",
            "if (present(x) != false) println(x.length)",
            "if (result(x) != null) println(x.length)",
            "if (null == result(x)) {} else println(x.length)",
            "if (present(x) && x.length > 0) println(x.length)",
            "if (!present(x) || x.length > 0) {}",
            "if (both(b = y, a = x)) println(x.length + y.length)",
            "if (predicate(x != null)) println(x.length)",
            "if (!present(x)) return; println(x.length)",
            "if (maybe(x) == true) println(x.length)",
            "ensureBoth(b = y, a = x); println(x.length + y.length)",
        ]
        let negative = [
            "present(x); println(x.length)",
            "if (!present(x)) println(x.length)",
            "if (absent(x)) println(x.length)",
            "if (result(x) == null) println(x.length)",
            "result(x); println(x.length)",
            "if (present(x) || present(y)) println(x.length)",
            "if (maybe(x) != false) println(x.length)",
            "if (maybe(x) == false) {} else println(x.length)",
        ]
        let sources = (positive + negative).enumerated().map { index, body in
            "package case\(index)\n" + declarations + "\nfun probe(x: String?, y: String?) { \(body) }"
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(positive.count) {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "\(path): \(errors)")
            }
            for path in paths.dropFirst(positive.count) {
                assertHasDiagnostic("KSWIFTK-SEMA-0026", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

    @Test
    func onlyGuaranteedInvocationsInitializeLocals() throws {
        let kinds = ["EXACTLY_ONCE", "AT_LEAST_ONCE", "AT_MOST_ONCE", "UNKNOWN", ""]
        let sources = kinds.enumerated().map { index, kind in
            """
            package invocation\(index)
            import kotlin.contracts.*
            @OptIn(ExperimentalContracts::class)
            fun invoke(tag: Int, block: () -> Unit) {
                contract { callsInPlace(block\(kind.isEmpty ? "" : ", InvocationKind.\(kind)")) }
                block()
            }
            fun probe(): Int {
                var x: Int
                invoke(block = { x = 5 }, tag = 1)
                return x
            }
            """
        }
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            for path in paths.prefix(2) {
                assertNoDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
            for path in paths.dropFirst(2) {
                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: diagnosticsForPath(path, in: ctx))
            }
        }
    }

    @Test
    func importedImplicationsNarrowCallArguments() throws {
        let libDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("kklib")
        try FileManager.default.createDirectory(at: libDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: libDir) }
        let manifest = """
        {"formatVersion": 1, "moduleName": "Contracts", "metadata": "metadata.bin"}
        """
        let record = MetadataRecord(
            kind: .function, mangledName: "_KK_present", fqName: "test.present", arity: 1,
            typeSignature: "F1<Q<Lkotlin_String;>,Z>",
            contractImplicationEffects: [ContractImplicationEffect(parameterIndex: 0, returnCondition: .returnsTrue, argumentCondition: .nonNull)],
            valueParameterNames: ["x"]
        )
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try MetadataEncoder().serialize([record]).write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)
        try withTemporaryFile(contents: "import test.present\nfun probe(x: String?) { if (present(x)) println(x.length) }") { path in
            let ctx = makeCompilationContext(inputs: [path], searchPaths: [libDir.path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
