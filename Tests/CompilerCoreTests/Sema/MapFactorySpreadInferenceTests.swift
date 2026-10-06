#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct MapFactorySpreadInferenceTests {
    @Test(arguments: ["linkedMapOf", "mutableMapOf", "hashMapOf", "mapOf"])
    func spreadRetainsPairKeyAndValueTypes(factory: String) throws {
        let source = """
        class Desc(val number: Int?, val fullName: String)

        fun f(): String? {
            val usage = \(factory)(*arrayOf(Desc(null, "x") to 0))
            return usage.iterator().next().key.fullName
        }

        fun mapped(): Int {
            val descs = listOf(Desc(null, "x"))
            val usage = \(factory)(*descs.map { it to 0 }.toTypedArray())
            for ((d, n) in usage) {
                val name: String = d.fullName
                return n + name.length
            }
            return 0
        }

        fun mixed(): Int {
            val pairs: Array<out Pair<Desc, Int>> = arrayOf(Desc(null, "x") to 0)
            val usage = \(factory)(Desc(1, "y") to 1, *pairs, Desc(2, "z") to 2)
            val key: Desc = usage.iterator().next().key
            val value: Int = usage.iterator().next().value
            return value + key.fullName.length
        }

        fun direct(): String = \(factory)(Desc(null, "x") to 0).iterator().next().key.fullName
        fun stringKeys(): Int = \(factory)(*arrayOf("x" to 0)).iterator().next().key.length
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors.map { "\($0.code): \($0.message)" })")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let desc = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Desc")]))
            let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == factory
            }
            #expect(calls.count == 5)
            for call in calls.prefix(4) {
                let type = try #require(sema.bindings.exprType(for: call))
                guard case let .classType(map) = sema.types.kind(of: type),
                      map.args.count == 2,
                      let key = projectedType(map.args[0]),
                      let value = projectedType(map.args[1]),
                      case let .classType(keyClass) = sema.types.kind(of: key)
                else {
                    Issue.record("Expected a map with concrete key/value types: \(sema.types.kind(of: type))")
                    continue
                }
                #expect(keyClass.classSymbol == desc)
                #expect(value == sema.types.intType)
            }
        }
    }

    private func projectedType(_ argument: TypeArg) -> TypeID? {
        switch argument {
        case let .invariant(type), let .in(type), let .out(type): type
        case .star: nil
        }
    }
}
#endif
