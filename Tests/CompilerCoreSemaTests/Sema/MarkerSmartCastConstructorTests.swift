#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct MarkerSmartCastConstructorTests {
    // KUU-2138: retain List<T> when the first flow fact is a marker check.
    @Test func originalReproducerInfersTheOuterTypeParameter() throws {
        try withTemporaryFile(contents: """
        interface Marker
        class View<T>(val values: List<T>)
        fun <T> wrap(values: List<T>): View<T> =
            if (values is Marker) View(values) else View(values)
        fun main() {}
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let wrap = try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern("wrap")]).first)
            let signature = try #require(sema.symbols.functionSignature(for: wrap))
            let calls = ast.arena.exprs.indices.map { ExprID(rawValue: Int32($0)) }.filter { id in
                guard case let .call(callee, _, _, _) = ast.arena.expr(id),
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return name == ctx.interner.intern("View")
            }
            #expect(calls.count == 2)
            for call in calls {
                #expect(sema.bindings.exprType(for: call) == signature.returnType)
                guard case let .call(_, _, arguments, _) = ast.arena.expr(call) else { continue }
                let argument = try #require(arguments.first)
                let argumentType = try #require(sema.bindings.exprType(for: argument.expr))
                #expect(sema.types.isSubtype(argumentType, signature.parameterTypes[0]))
            }
        }
    }

    @Test(arguments: [
        "if (values is Marker) View(values) else View(values)",
        "if (values is Marker) View<T>(values) else View<T>(values)",
        "if (values is Marker?) View(values) else View(values)",
        "if (values is Marker?) { acceptMarker(values); View(values) } else View(values)",
        "if (values !is Marker) View(values) else View(values)",
        "if (values is Marker) { acceptMarker(values); acceptList(values); View(values) } else View(values)",
        "if (values is Marker) { val view = View(values); view } else View(values)",
        "if (values is Marker && values is Other) { acceptMarker(values); acceptOther(values); View(values) } else View(values)",
        "if (values is Marker && values is Other) { val view = View(values); view } else View(values)"
    ])
    func preservesGenericListContract(body: String) throws {
        try withTemporaryFile(contents: """
        interface Marker
        interface Other
        class View<T>(val values: List<T>)
        fun acceptMarker(values: Marker) {}
        fun acceptOther(values: Other) {}
        fun <T> acceptList(values: List<T>) {}
        fun <T> wrap(values: List<T>): View<T> = \(body)
        fun concrete(values: List<Int>): View<Int> =
            if (values is Marker) View(values) else View(values)
        fun nullable(values: List<Int>?): View<Int>? =
            if (values is Marker) View(values) else null
        fun nullableElements(values: List<Int?>): View<Int?> =
            if (values is Marker) View(values) else View(values)
        fun <T : Any> bounded(values: T) {
            if (values is Marker?) acceptMarker(values)
        }
        fun main() {}
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test(arguments: [
        "fun <T> bad(values: Any): View<T>? = if (values is Marker) View<T>(values) else null",
        "fun bad(values: List<String>): View<Int>? = if (values is Marker) View<Int>(values) else null",
        "fun bad(values: List<Int?>): View<Int>? = if (values is Marker) View<Int>(values) else null",
        "fun bad(values: List<Int>): Marker = if (values is Marker) values else values",
        "fun bad(values: List<Int>): Marker { if (values is Marker) return values; return values }",
        "fun bad(values: List<Int>?): View<Int>? = if (values is Marker?) View(values) else null",
        "fun <T> bad(values: T) { if (values is Marker?) acceptMarker(values) }",
        "fun <T : Any?> bad(values: T) { if (values is Marker?) acceptMarker(values) }",
        "fun <T : Any> bad(values: T?) { if (values is Marker?) acceptMarker(values) }"
    ])
    func rejectsMissingContracts(declaration: String) throws {
        try withTemporaryFile(contents: """
        interface Marker
        class View<T>(val values: List<T>)
        fun acceptMarker(values: Marker) {}
        \(declaration)
        """) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-TYPE-0001" || $0.code == "KSWIFTK-SEMA-0002"
            })
        }
    }
}
#endif
