#if canImport(Testing)
@testable import CompilerCore
import Testing

// KUU-853 regression: a bare reference to a sibling extension property inside
// another same-receiver extension body (`id` inside `label`'s getter, `label`
// inside `describe`) must lower to that property's getter called on the
// implicit receiver — not `loadGlobal` on a global slot that is never
// initialized (Int reads as 0, String reads as null; this made
// `Worker.toString()` print "Worker null" and the `Worker.name` fallback
// print "worker 0").
extension BuildKIRRegressionTests {
    @Test func testExtensionPropertySiblingReferenceDispatchesToGetterOnImplicitReceiver() throws {
        let source = """
        package test

        class Box(val raw: Int)

        val Box.id: Int
            get() = raw

        val Box.label: String
            get() = "box $id"

        fun Box.describe(): String = "desc $label"
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let interner = ctx.interner
        let functions = findAllKIRFunctions(in: module)
        let package = [interner.intern("test")]

        func extensionProperty(named name: String) throws -> (property: SymbolID, getter: SymbolID) {
            let propName = interner.intern(name)
            let property = try #require(
                sema.symbols.lookupAll(fqName: package + [propName]).first(where: {
                    sema.symbols.symbol($0)?.kind == .property
                }),
                "extension property \(name) not found"
            )
            let getter = try #require(
                sema.symbols.extensionPropertyGetterAccessor(for: property),
                "extension property \(name) has no registered getter"
            )
            return (property, getter)
        }

        func functionBody(of symbol: SymbolID, named debugName: String) throws -> [KIRInstruction] {
            try #require(
                functions.first(where: { $0.symbol == symbol }),
                "KIR body for \(debugName) not found"
            ).body
        }

        func expectGetterCall(
            in body: [KIRInstruction],
            to getter: SymbolID,
            insteadOf property: SymbolID,
            context: String
        ) {
            #expect(
                body.contains { instruction in
                    guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else {
                        return false
                    }
                    return symbol == getter && arguments.count == 1
                },
                "\(context) should call the sibling property's getter on the implicit receiver"
            )
            #expect(
                !body.contains { instruction in
                    guard case let .loadGlobal(_, symbol) = instruction else { return false }
                    return symbol == property
                },
                "\(context) must not loadGlobal the extension property symbol"
            )
        }

        let idProp = try extensionProperty(named: "id")
        let labelProp = try extensionProperty(named: "label")

        // `label`'s getter references `id` bare on the implicit Box receiver.
        let labelGetterBody = try functionBody(of: labelProp.getter, named: "label$get")
        try expectGetterCall(
            in: labelGetterBody,
            to: idProp.getter,
            insteadOf: idProp.property,
            context: "label getter's `id` read"
        )

        // `describe` references `label` bare on the implicit Box receiver.
        let describeSymbol = try #require(
            sema.symbols.lookupAll(fqName: package + [interner.intern("describe")]).first(where: {
                sema.symbols.symbol($0)?.kind == .function
            }),
            "Box.describe symbol not found"
        )
        let describeBody = try functionBody(of: describeSymbol, named: "describe")
        try expectGetterCall(
            in: describeBody,
            to: labelProp.getter,
            insteadOf: labelProp.property,
            context: "describe's `label` read"
        )
    }
}
#endif
