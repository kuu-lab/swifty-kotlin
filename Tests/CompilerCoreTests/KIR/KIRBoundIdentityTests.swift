#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite struct KIRBoundIdentityTests {
    @Test func itableAndVtableChooseTheMatchingBound() throws {
        let ctx = makeBoundIdentityContext("""
        interface Bounded {
            fun <T : CharSequence> echo(value: T): T
            fun <T : Number> echo(value: T): T
        }
        open class Base : Bounded {
            override fun <T : CharSequence> echo(value: T): T = value
            override fun <T : Number> echo(value: T): T = value
        }
        class Child : Base() {
            override fun <E : Number> echo(value: E): E = value
        }
        class Wrapped(base: Bounded) : Bounded by base
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        func owner(_ name: String) throws -> SymbolID {
            try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
        }
        func methods(_ name: String) -> [SymbolID] {
            sema.symbols.lookupAll(fqName: [name, "echo"].map(ctx.interner.intern))
        }
        let base = try owner("Base")
        let child = try owner("Child")
        let childMethod = try #require(methods("Child").first)
        let childSignature = try #require(sema.symbols.functionSignature(for: childMethod))
        let childLayout = try #require(sema.symbols.nominalLayout(for: child))
        for method in methods("Bounded") {
            let signature = try #require(sema.symbols.functionSignature(for: method))
            let target = try #require(kirFindOverrideMethod(for: method, in: base, sema: sema, interner: ctx.interner))
            let targetSignature = try #require(sema.symbols.functionSignature(for: target))
            #expect(methodUpperBoundsMatch(source: signature, target: targetSignature,
                                          sourceOwner: try owner("Bounded"), targetOwner: base, types: sema.types))
            let numberBound = methodUpperBoundsMatch(source: signature, target: childSignature,
                                                    sourceOwner: try owner("Bounded"), targetOwner: child, types: sema.types)
            #expect(kirFindOverrideMethod(for: method, in: child, sema: sema, interner: ctx.interner) == (numberBound ? childMethod : target))
            #expect((childLayout.vtableSlots[target] == childLayout.vtableSlots[childMethod]) == numberBound)
        }
        let wrapped = try owner("Wrapped")
        for forwarder in sema.symbols.classDelegationForwardingMethodSymbols(forClass: wrapped) {
            let info = try #require(sema.symbols.classDelegationForwardingMethodInfo(for: forwarder))
            let signature = try #require(sema.symbols.functionSignature(for: info.interfaceMethodSymbol))
            let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == forwarder })
            let targets = kirCalls(in: function.body).compactMap(\.symbol).filter {
                sema.symbols.symbol($0)?.name == ctx.interner.intern("echo") && $0 != forwarder
            }
            #expect(!targets.isEmpty)
            for target in targets {
                let targetOwner = try #require(sema.symbols.parentSymbol(for: target))
                // Forwarders are tested after the prerequisite binder repair;
                // source implementation candidates already own their binders.
                guard sema.symbols.classDelegationForwardingMethodInfo(for: target) == nil else { continue }
                let targetSignature = try #require(sema.symbols.functionSignature(for: target))
                #expect(methodUpperBoundsMatch(source: signature, target: targetSignature,
                                              sourceOwner: try owner("Bounded"), targetOwner: targetOwner, types: sema.types))
            }
        }
    }

    @Test func inheritedImplementationUsesTheConcreteInterfaceArguments() throws {
        let ctx = makeBoundIdentityContext("""
        interface Generic<A> { fun <T : A> echo(value: T): T }
        open class Base<B> { open fun <T : B> echo(value: T): T = value }
        class Child : Base<Number>(), Generic<Number>
        class Wrapped(base: Generic<Number>) : Generic<Number> by base
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let method = try #require(sema.symbols.lookup(fqName: ["Generic", "echo"].map(ctx.interner.intern)))
        let implementation = try #require(sema.symbols.lookup(fqName: ["Base", "echo"].map(ctx.interner.intern)))
        let child = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Child")]))
        #expect(kirFindOverrideMethod(for: method, in: child, sema: sema, interner: ctx.interner) == implementation)
        let wrapped = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Wrapped")]))
        let forwarder = try #require(sema.symbols.classDelegationForwardingMethodSymbols(forClass: wrapped).first)
        let module = try #require(ctx.kir)
        let function = try #require(findAllKIRFunctions(in: module).first { $0.symbol == forwarder })
        #expect(kirCalls(in: function.body).contains { $0.symbol == implementation },
                "Expected \(implementation), got: \(kirCalls(in: function.body).compactMap(\.symbol)); body: \(function.body)")
    }

    @Test func methodBindersDoNotMatchDifferentParameterShapes() throws {
        let ctx = makeBoundIdentityContext("""
        class Box<T>
        interface Input {
            fun <T : Number> echo(value: T): T
            fun <T : Number> echo(value: Box<T>): Box<T>
            fun <T : CharSequence> echo(value: T): T
        }
        open class Base : Input {
            override fun <T : Number> echo(value: T): T = value
            override fun <T : Number> echo(value: Box<T>): Box<T> = value
            override fun <T : CharSequence> echo(value: T): T = value
        }
        class Child : Base() {
            override fun <E : Number> echo(value: Box<E>): Box<E> = value
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let child = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Child")]))
        let override = try #require(sema.symbols.lookup(fqName: ["Child", "echo"].map(ctx.interner.intern)))
        let layout = try #require(sema.symbols.nominalLayout(for: child))
        let baseMethods = sema.symbols.lookupAll(fqName: ["Base", "echo"].map(ctx.interner.intern))
        for base in baseMethods {
            let signature = try #require(sema.symbols.functionSignature(for: base))
            let isBox: Bool = if case .classType = sema.types.kind(of: signature.parameterTypes[0]) { true } else { false }
            #expect((layout.vtableSlots[base] == layout.vtableSlots[override]) == isBox)
        }
        for method in sema.symbols.lookupAll(fqName: ["Input", "echo"].map(ctx.interner.intern)) {
            let signature = try #require(sema.symbols.functionSignature(for: method))
            let isBox: Bool = if case .classType = sema.types.kind(of: signature.parameterTypes[0]) { true } else { false }
            let target = try #require(kirFindOverrideMethod(for: method, in: child, sema: sema, interner: ctx.interner))
            #expect((target == override) == isBox)
        }
    }


    @Test func methodBinderAlignmentPreservesDeclarationVariance() throws {
        let ctx = makeBoundIdentityContext("""
        class Payload<out T>
        interface Variant { fun <T : Number> read(value: Payload<out T>): Int }
        open class Base : Variant {
            override fun <T : Number> read(value: Payload<out T>): Int = 1
        }
        class Child : Base() {
            override fun <E : Number> read(value: Payload<E>): Int = 2
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let child = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Child")]))
        let baseMethod = try #require(sema.symbols.lookup(fqName: ["Base", "read"].map(ctx.interner.intern)))
        let override = try #require(sema.symbols.lookup(fqName: ["Child", "read"].map(ctx.interner.intern)))
        let interface = try #require(sema.symbols.lookup(fqName: ["Variant", "read"].map(ctx.interner.intern)))
        let layout = try #require(sema.symbols.nominalLayout(for: child))
        #expect(layout.vtableSlots[baseMethod] == layout.vtableSlots[override])
        #expect(kirFindOverrideMethod(for: interface, in: child, sema: sema, interner: ctx.interner) == override)
    }


    @Test func upperBoundIdentityPreservesDeclarationVariance() throws {
        let ctx = makeBoundIdentityContext("""
        interface Payload<out A>
        interface Variant { fun <T : Payload<out Number>> echo(value: T): T }
        class Impl : Variant {
            override fun <E : Payload<Number>> echo(value: E): E = value
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let impl = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Impl")]))
        let method = try #require(sema.symbols.lookup(fqName: ["Variant", "echo"].map(ctx.interner.intern)))
        let override = try #require(sema.symbols.lookup(fqName: ["Impl", "echo"].map(ctx.interner.intern)))
        #expect(kirFindOverrideMethod(for: method, in: impl, sema: sema, interner: ctx.interner) == override)
    }

}
#endif
