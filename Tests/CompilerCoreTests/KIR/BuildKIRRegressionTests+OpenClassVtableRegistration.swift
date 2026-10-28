#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    // KUU-2060: open owners need registrations even without known subclasses.
    @Test
    func openClassWithoutSubtypesRegistersVirtualMethodsAndGetters() throws {
        let context = makeContextFromSource("""
        open class Leaf {
            open fun value(): Int = 7
            open val count: Int get() = 9
        }
        fun probe(): Int {
            val leaf = Leaf()
            return leaf.value() + leaf.count
        }
        """)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let leaf = try #require(sema.symbols.lookup(fqName: [context.interner.intern("Leaf")]))
        #expect(sema.symbols.directSubtypes(of: leaf).isEmpty)
        let body = try findKIRFunctionBody(named: "probe", in: try #require(context.kir), interner: context.interner)
        let constants = body.reduce(into: [KIRExprID: Int]()) { values, instruction in
            if case let .constValue(result, .intLiteral(value)) = instruction {
                values[result] = Int(value)
            }
        }
        let registered = Set(body.compactMap { instruction -> Int? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  context.interner.resolve(callee) == "kk_object_register_vtable_method",
                  arguments.count == 3 else { return nil }
            return constants[arguments[1]]
        })
        let dispatched = Set(body.compactMap { instruction -> Int? in
            guard case let .virtualCall(_, _, _, _, _, _, _, .vtable(slot)) = instruction else { return nil }
            return slot
        })
        #expect(!dispatched.isEmpty)
        let property = try #require(sema.symbols.lookup(fqName: ["Leaf", "count"].map(context.interner.intern)))
        let layout = try #require(sema.symbols.nominalLayout(for: leaf))
        let getterSlots = Set(layout.vtableSlots.compactMap { accessor, slot -> Int? in
            guard let decoded = SyntheticSymbolScheme.decodedPropertyAccessor(accessor),
                  decoded.property == property, decoded.kind == .getter else { return nil }
            return slot
        })
        #expect(getterSlots.count == 1)
        #expect(getterSlots.isSubset(of: registered))
        #expect(dispatched.isSubset(of: registered))
        #expect(extractVirtualCallees(from: body, interner: context.interner).contains("value"))
    }
}
#endif
