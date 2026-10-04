#if canImport(Testing)
@testable import CompilerCore
import Testing

// Enum values use an ordinal-backed representation in KIR. Entry-body
// overrides therefore need a generated ordinal switch rather than a heap-backed
// anonymous subclass.
extension LoweringPassRegressionTests {
    @Test
    func testEnumEntryBodyOverridesResolveAndLowerThroughOrdinalDispatch() throws {
        let source = """
        enum class E(val w: Int) {
            X(1) {
                override fun f() = "x"
            },
            Y(2) {
                override fun f() = "y"
            };
            abstract fun f(): String
        }

        enum class Op {
            PLUS {
                override fun apply(a: Int, b: Int) = a + b
            },
            TIMES {
                override fun apply(a: Int, b: Int) = a * b
            };
            abstract fun apply(a: Int, b: Int): Int
        }

        fun main() {
            println(E.X.f())
            println(Op.TIMES.apply(2, 3))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryBody",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "enum entry body references should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let dispatchFunctions = functions.filter {
                ctx.interner.resolve($0.name).hasPrefix("$enumEntryDispatch$")
            }
            #expect(dispatchFunctions.count == 2)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let mainCallees = extractCallees(from: mainBody, interner: ctx.interner)
            #expect(mainCallees.filter { $0.hasPrefix("$enumEntryDispatch$") }.count == 2)

            for dispatch in dispatchFunctions {
                let targetCalls = dispatch.body.compactMap { instruction -> (SymbolID, Int)? in
                    guard case let .call(symbol, callee, arguments, _, _, _, _, _) = instruction,
                          let symbol = symbol,
                          (ctx.interner.resolve(callee) == "f" || ctx.interner.resolve(callee) == "apply")
                    else {
                        return nil
                    }
                    return (symbol, arguments.count)
                }
                #expect(targetCalls.count == 2)
                #expect(targetCalls.allSatisfy { $0.1 == 1 || $0.1 == 3 })
                #expect(targetCalls.allSatisfy { symbol, _ in
                    functions.contains { $0.symbol == symbol }
                })
            }
        }
    }

    @Test
    func testEnumEntryBodyOverrideInheritedFromInterfaceUsesOrdinalDispatch() throws {
        let source = """
        interface F {
            fun f(): String
        }

        enum class E : F {
            X {
                override fun f() = "x"
            },
            Y {
                override fun f() = "y"
            };
        }

        fun main() {
            println(E.X.f())
            println(E.Y.f())
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntryBodyInterface",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "interface-inherited enum entry overrides should resolve: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let functions = findAllKIRFunctions(in: module)
            let dispatchFunctions = functions.filter {
                ctx.interner.resolve($0.name).hasPrefix("$enumEntryDispatch$")
            }
            #expect(dispatchFunctions.count == 1)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            #expect(extractCallees(from: mainBody, interner: ctx.interner).contains {
                $0.hasPrefix("$enumEntryDispatch$")
            })
        }
    }
}
#endif
