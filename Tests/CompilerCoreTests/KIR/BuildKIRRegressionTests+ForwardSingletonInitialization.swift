#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    @Test(arguments: [false, true])
    func testForwardCompanionReadHasLazyGuardBeforeGlobalLoad(separateFiles: Bool) throws {
        let consumer = """
        fun Companion(): Int = 7
        fun collisionControl(): Int = Companion()
        fun catchControl(): Int {
            try { return Failing.value } catch (e: Throwable) { return 8 }
        }
        class Consumer {
            fun value(): Int = Point.NORTH.x
            fun constant(): Int = Point.CONSTANT
        }
        """
        let point = """
        data class Point(val x: Int) {
            companion object {
                const val CONSTANT = 9
                val NORTH = Point(-1)
            }
        }
        object Failing { val value: Int = error("boom") }
        """
        let ctx = makeContextFromSources(separateFiles ? [consumer, point] : [consumer + "\n" + point])
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError)
        let module = try #require(ctx.kir)
        let functions = findAllKIRFunctions(in: module)
        let valueSymbol = try sourceSymbol(named: "value", in: ctx)
        let value = try #require(functions.first { $0.symbol == valueSymbol })
        let guardIndex = try #require(value.body.firstIndex {
            if case let .call(symbol?, callee, _, _, _, _, _, _) = $0 {
                return ctx.interner.resolve(callee).hasPrefix("__companion_lazy_init_")
                    && functions.contains { $0.symbol == symbol }
            }
            return false
        })
        let loadIndex = try #require(value.body.firstIndex {
            if case .loadGlobal = $0 { return true }
            return false
        })
        #expect(guardIndex < loadIndex)
        let constantSymbol = try sourceSymbol(named: "constant", in: ctx)
        let constant = try #require(functions.first { $0.symbol == constantSymbol })
        #expect(!constant.body.contains {
            if case let .call(_, callee, _, _, _, _, _, _) = $0 {
                return ctx.interner.resolve(callee).contains("lazy_init")
            }
            return false
        })
        let collisionSymbol = try sourceSymbol(named: "collisionControl", in: ctx)
        let collision = try #require(functions.first { $0.symbol == collisionSymbol })
        let userMarkerSymbol = try sourceSymbol(named: "Companion", in: ctx)
        #expect(collision.body.contains {
            if case let .call(symbol, _, _, _, _, _, _, _) = $0 { return symbol == userMarkerSymbol }
            return false
        })
        let catchSymbol = try sourceSymbol(named: "catchControl", in: ctx)
        let catching = try #require(functions.first { $0.symbol == catchSymbol })
        let thrownSlot = try #require(catching.body.compactMap { instruction -> KIRExprID? in
            if case let .call(_, callee, _, _, canThrow, thrownResult, _, _) = instruction,
               ctx.interner.resolve(callee).hasPrefix("__object_lazy_init_") {
                #expect(canThrow)
                return thrownResult
            }
            return nil
        }.first)
        #expect(catching.body.contains {
            if case let .jumpIfNotNull(value, _) = $0 { return value == thrownSlot }
            return false
        })
        // Every symbolic call in these consumers must resolve after the owning
        // declarations are lowered, including deferred singleton guards.
        for function in [value, constant, collision, catching] {
            for instruction in function.body {
                if case let .call(symbol?, _, _, _, _, _, _, _) = instruction {
                    #expect(functions.contains { $0.symbol == symbol }
                        || ctx.sema?.symbols.externalLinkName(for: symbol) != nil)
                }
            }
        }
    }
}
#endif
