#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct NullBranchMutableMapTypeArgumentTests {
    @Test(arguments: [false, true])
    func attributesMapOfKeepsMutableMapTypeArgumentsAfterNullInitialization(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        if allowDefaultStdlibLibrary { TestStdlibCache.shared.prepare() }
        let source = """
        fun attributesMapOf(vararg pairs: String?): Map<String, String> {
            var result: MutableMap<String, String>? = null
            for (i in 0..pairs.size - 1 step 2) {
                val k = pairs[i]
                val v = pairs[i + 1]
                if (k != null && v != null) {
                    if (result == null) result = linkedMapOf()
                    val typedResult: MutableMap<String, String> = result
                    val size: Int = result.size
                    result.put(k, v)
                }
            }
            return result ?: emptyMap()
        }

        fun minimalReproduction() {
            var result: MutableMap<String, String>? = null
            if (result == null) result = linkedMapOf()
            result.put("key", "value")
        }

        fun nonNullInitializer() {
            var result: MutableMap<String, String> = linkedMapOf()
            result.put("key", "value")
        }

        fun nullableGuard(result: MutableMap<String, String>?) {
            if (result == null) return
            result.put("key", "value")
        }

        fun explicitNotNullAssertion() {
            var result: MutableMap<String, String>? = null
            if (result == null) result = linkedMapOf()
            result!!.put("key", "value")
        }

        class Box<T> { fun set(value: T) {} }
        fun genericBoxControl() {
            var box: Box<String>? = null
            if (box == null) box = Box()
            box.set("value")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path], emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let putCall = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .memberCall(_, name, _, _, _) = expr else { return false }
                return ctx.interner.resolve(name) == "put"
            })
            guard case let .memberCall(receiver, _, _, _, _) = ast.arena.expr(putCall) else {
                Issue.record("Expected MutableMap.put member call")
                return
            }
            let receiverType = try #require(sema.bindings.exprType(for: receiver))
            #expect(
                sema.types.displayName(of: receiverType, symbols: sema.symbols, interner: ctx.interner)
                    == "MutableMap<String, String>",
                "Receiver type was \(sema.types.displayName(of: receiverType, symbols: sema.symbols, interner: ctx.interner))"
            )
        }
    }
}
#endif
