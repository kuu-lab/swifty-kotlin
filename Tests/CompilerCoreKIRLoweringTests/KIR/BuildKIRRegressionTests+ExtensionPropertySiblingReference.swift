#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-853 regression: a bare reference to a sibling extension property inside
// another same-receiver extension body (`id` inside `label`'s getter, `label`
// inside `describe`) must lower to that property's getter called on the
// implicit receiver — not `loadGlobal` on a global slot that is never
// initialized (Int reads as 0, String reads as null; this made
// `Worker.toString()` print "Worker null" and the `Worker.name` fallback
// print "worker 0").
extension BuildKIRRegressionTests {
    @Test func testImplicitExtensionPropertySelectsCompatibleReceiver() throws {
        let ctx = makeContextFromSource("""
        package test

        class Other
        interface Sender { val raw: Boolean }
        class Producer(override val raw: Boolean) : Sender

        val Other.closed: Boolean
            get() = false
        val Sender.closed: Boolean
            get() = raw

        fun Producer.inspect(): Boolean = closed
        """)
        try runToKIR(ctx)
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let properties = sema.symbols.lookupAll(fqName: [ctx.interner.intern("test"), ctx.interner.intern("closed")])
        let senderProperty = try #require(properties.first { symbol in
            guard let receiver = sema.symbols.extensionPropertyReceiverType(for: symbol),
                  case let .classType(classType) = sema.types.kind(of: receiver)
            else { return false }
            return sema.symbols.symbol(classType.classSymbol)?.name == ctx.interner.intern("Sender")
        })
        let getter = try #require(sema.symbols.extensionPropertyGetterAccessor(for: senderProperty))
        let inspect = try #require(findAllKIRFunctions(in: module).first {
            $0.name == ctx.interner.intern("inspect")
        })
        #expect(inspect.body.contains { instruction in
            guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction else { return false }
            return symbol == getter && arguments.count == 1
        })
        #expect(!inspect.body.contains { instruction in
            guard case let .loadGlobal(_, symbol) = instruction else { return false }
            return properties.contains(symbol)
        })
    }

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
        expectGetterCall(
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
        expectGetterCall(
            in: describeBody,
            to: labelProp.getter,
            insteadOf: labelProp.property,
            context: "describe's `label` read"
        )
    }

    // KUU-3914: an unqualified extension property referenced inside a
    // receiver-typed lambda (`buildString { ... }`) binds to the enclosing
    // receiver-tower entry — the extension's `this` — not to the lambda's own
    // receiver. KIR must capture that enclosing receiver and call the sibling
    // getter on it; falling back to `loadGlobal` reads a global slot that is
    // never initialized (the ktor-http `URLBuilder.authority` regression).
    @Test func testExtensionPropertyInsideReceiverLambdaCallsGetterOnCapturedReceiver() throws {
        let ctx = makeContextFromSource("""
        package test

        class URLBuilder(var encodedUser: String = "", var encodedPassword: String = "")

        val URLBuilder.encodedUserAndPassword: String
            get() = buildString {
                append(encodedUser)
            }

        val URLBuilder.authority: String
            get() = buildString {
                append(encodedUserAndPassword)
                append(encodedUser)
            }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let urlBuilder = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("test"), ctx.interner.intern("URLBuilder"),
        ]))
        let property = try #require(
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("test"), ctx.interner.intern("encodedUserAndPassword"),
            ]).first(where: { sema.symbols.symbol($0)?.kind == .property }),
            "encodedUserAndPassword extension property not found"
        )
        let getter = try #require(
            sema.symbols.extensionPropertyGetterAccessor(for: property),
            "encodedUserAndPassword has no registered getter"
        )
        let lambdas = try findKIRLambdaFunctions(in: ctx).filter { function in
            function.body.contains { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == getter
            }
        }
        #expect(
            lambdas.count == 1,
            "Only authority's buildString lambda must invoke the sibling extension getter"
        )
        let lambda = try #require(lambdas.first)
        #expect(
            lambda.params.contains { parameter in
                guard case let .classType(type) = sema.types.kind(of: parameter.type) else {
                    return false
                }
                return type.classSymbol == urlBuilder
            },
            "The receiver lambda must capture the enclosing URLBuilder receiver"
        )
        #expect(
            lambda.body.contains { instruction in
                guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                      symbol == getter, arguments.count == 1,
                      let receiverType = module.arena.exprType(arguments[0]),
                      case let .classType(type) = sema.types.kind(of: receiverType)
                else { return false }
                return type.classSymbol == urlBuilder
            },
            "The sibling getter must be called on the captured URLBuilder receiver"
        )
        #expect(
            !lambda.body.contains { instruction in
                guard case let .loadGlobal(_, symbol) = instruction else { return false }
                return symbol == property
            },
            "The extension property must not be read through loadGlobal"
        )
    }

    // KUU-3914, nested form: `with(StringBuilder()) { buildString { ... } }`
    // pushes two receiver-lambda entries in front of the enclosing `Outer`
    // receiver; the extension property read must still reach it through
    // transitive lambda captures.
    @Test func testNestedReceiverLambdasTransitivelyCaptureOuterExtensionReceiver() throws {
        let ctx = makeContextFromSource("""
        package test

        class Outer(val tag: String)

        val Outer.other: String
            get() = "other-" + tag

        fun Outer.nested(): String = with(StringBuilder()) {
            buildString {
                append(other)
            }
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let outer = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("test"), ctx.interner.intern("Outer"),
        ]))
        let property = try #require(
            sema.symbols.lookupAll(fqName: [
                ctx.interner.intern("test"), ctx.interner.intern("other"),
            ]).first(where: { sema.symbols.symbol($0)?.kind == .property }),
            "other extension property not found"
        )
        let getter = try #require(
            sema.symbols.extensionPropertyGetterAccessor(for: property),
            "other has no registered getter"
        )
        let lambdas = try findKIRLambdaFunctions(in: ctx).filter { function in
            function.body.contains { instruction in
                guard case let .call(symbol?, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == getter
            }
        }
        #expect(
            lambdas.count == 1,
            "Only the innermost buildString lambda must invoke the extension getter"
        )
        let lambda = try #require(lambdas.first)
        #expect(
            lambda.params.contains { parameter in
                guard case let .classType(type) = sema.types.kind(of: parameter.type) else {
                    return false
                }
                return type.classSymbol == outer
            },
            "The innermost lambda must transitively capture the Outer receiver"
        )
        #expect(
            lambda.body.contains { instruction in
                guard case let .call(symbol, _, arguments, _, _, _, _, _) = instruction,
                      symbol == getter, arguments.count == 1,
                      let receiverType = module.arena.exprType(arguments[0]),
                      case let .classType(type) = sema.types.kind(of: receiverType)
                else { return false }
                return type.classSymbol == outer
            },
            "The extension getter must be called on the captured Outer receiver"
        )
        #expect(
            !lambda.body.contains { instruction in
                guard case let .loadGlobal(_, symbol) = instruction else { return false }
                return symbol == property
            },
            "The extension property must not be read through loadGlobal"
        )
    }
}
#endif
