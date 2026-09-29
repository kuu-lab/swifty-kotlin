#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    // Regression coverage for compound assignment / increment and plain
    // assignment through explicit-receiver property targets whose accessors are
    // only partially custom, interface-typed, or extension-declared. Each used
    // to emit a call to a symbol that does not exist (`get`/`set`/the bare
    // property name), which failed KIR verification or linking.

    private func mainCalleeNames(_ source: String) throws -> (callees: [String], virtualCallees: [String], calls: [(SymbolID?, String)], ctx: CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)
        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        var calls: [(SymbolID?, String)] = []
        var virtualCallees: [String] = []
        for instruction in body {
            switch instruction {
            case let .call(symbol, callee, _, _, _, _, _, _):
                calls.append((symbol, ctx.interner.resolve(callee)))
            case let .virtualCall(_, callee, _, _, _, _, _, _):
                virtualCallees.append(ctx.interner.resolve(callee))
            default:
                break
            }
        }
        return (calls.map(\.1), virtualCallees, calls, ctx)
    }

    @Test func testCompoundAssignOnCustomSetterOnlyPropertyLoadsFieldAndCallsSetter() throws {
        let result = try mainCalleeNames("""
        class A {
            var total: Int = 0
                set(v) { field = v * 2 }
        }
        fun main() {
            val a = A()
            a.total += 1
        }
        """)
        #expect(result.callees.contains("kk_array_get_inbounds"), "default getter half must read the backing field, got: \(result.callees)")
        #expect(result.callees.contains("set"), "custom setter half must call the setter accessor, got: \(result.callees)")
        #expect(!result.callees.contains("get"), "no getter accessor exists for a default getter, got: \(result.callees)")
    }

    @Test func testCompoundAssignOnCustomGetterOnlyPropertyCallsGetterAndStoresField() throws {
        let result = try mainCalleeNames("""
        class A {
            var total: Int = 0
                get() = field + 100
        }
        fun main() {
            val a = A()
            a.total += 1
        }
        """)
        #expect(result.callees.contains("get"), "custom getter half must call the getter accessor, got: \(result.callees)")
        #expect(result.callees.contains("kk_array_set"), "default setter half must write the backing field, got: \(result.callees)")
        #expect(!result.callees.contains("set"), "no setter accessor exists for a default setter, got: \(result.callees)")
    }

    @Test func testCompoundAssignThroughInterfaceTypedVarUsesItableGetterAndSetter() throws {
        let result = try mainCalleeNames("""
        interface IntBox { var n: Int }
        class IB(override var n: Int) : IntBox
        fun main() {
            val b: IntBox = IB(1)
            b.n += 2
            b.n++
        }
        """)
        #expect(result.virtualCallees.filter { $0 == "get" }.count == 2, "each read-modify-write must read via the itable getter, got: \(result.virtualCallees)")
        #expect(result.virtualCallees.filter { $0 == "set" }.count == 2, "each read-modify-write must write via the itable setter, got: \(result.virtualCallees)")
        #expect(!result.callees.contains("n"), "must not call the bare property name, got: \(result.callees)")
    }

    @Test func testAssignToExtensionVarCallsSetterAccessor() throws {
        let result = try mainCalleeNames("""
        class Foo(val v: Int)
        var Foo.tag: String
            get() = "tag$v"
            set(value) { println(value) }
        fun main() {
            val f = Foo(5)
            f.tag = "zz"
        }
        """)
        let symbols = try #require(result.ctx.sema?.symbols)
        let setters = Set(symbols.allSymbols().compactMap { symbol -> SymbolID? in
            guard symbol.kind == .property, result.ctx.interner.resolve(symbol.name) == "tag" else { return nil }
            return symbols.extensionPropertySetterAccessor(for: symbol.id)
        })
        #expect(!setters.isEmpty)
        #expect(result.calls.contains { call in
            guard let symbol = call.0 else { return false }
            return call.1 == "set" && setters.contains(symbol)
        }, "expected a call to the extension setter accessor, got: \(result.callees)")
        #expect(!result.callees.contains("tag"), "must not call the bare property name, got: \(result.callees)")
    }
}
#endif
