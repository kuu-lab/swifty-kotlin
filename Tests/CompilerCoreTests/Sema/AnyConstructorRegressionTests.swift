#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for KSP-805: implicit kotlin.Any must remain the
/// nominal root without becoming an explicit `super()` delegation target.
@Suite
struct AnyConstructorRegressionTests {
    @Test(arguments: [
        "MutableList<Inter<TSubject, Call>>",
        "MutableList<(Call) -> Unit>",
    ])
    func secondaryDelegationContextualizesEmptyGenericFactory(parameterType: String) throws {
        let source = """
        typealias Inter<TSubject, Call> = (Call) -> Unit
        class P<TSubject : Any, Call : Any>(val f: \(parameterType)) {
            constructor() : this(mutableListOf())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Empty factories must use the delegated parameter type: \(errors)")
        let sema = try #require(ctx.sema)
        #expect(delegationBindings(for: "P", sema: sema, interner: ctx.interner).count == 1)
    }

    @Test
    func secondarySuperDelegationSubstitutesOwnerTypeArguments() throws {
        let source = """
        typealias Action<T> = (T) -> Unit
        open class Base<T>(val actions: MutableList<Action<T>>)
        class Derived<U> : Base<U> {
            constructor() : super(mutableListOf())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "super() must substitute Base<T> with Base<U>: \(errors)")
        let sema = try #require(ctx.sema)
        #expect(delegationBindings(for: "Derived", target: "Base", sema: sema, interner: ctx.interner).count == 1)
    }

    @Test
    func secondaryDelegationIgnoresNominallyIncompatibleOverload() throws {
        let source = """
        typealias Action<T> = (T) -> Unit
        class P<T>(val actions: MutableList<Action<T>>) {
            constructor() : this(mutableListOf())
            constructor(label: String) : this()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "A String overload must not block contextual inference: \(errors)")
        let sema = try #require(ctx.sema)
        #expect(delegationBindings(for: "P", sema: sema, interner: ctx.interner).count == 2)
    }

    @Test
    func secondaryDelegationKeepsConflictingOverloadsUnresolved() throws {
        let source = """
        typealias Action<T> = (T) -> Unit
        class P<T> {
            constructor(actions: MutableList<Action<T>>)
            constructor(items: MutableList<Int>)
            constructor() : this(mutableListOf())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "Conflicting expected types must not pick an arbitrary overload")
        let sema = try #require(ctx.sema)
        #expect(delegationBindings(for: "P", sema: sema, interner: ctx.interner).isEmpty)
    }

    @Test
    func secondaryDelegationContextualizesNamedArgumentWithDefaultParameter() throws {
        let source = """
        typealias Action<T> = (T) -> Unit
        class P<T>(val label: String = "default", val actions: MutableList<Action<T>>) {
            constructor() : this(actions = mutableListOf())
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Named delegation must use parameter mapping: \(errors)")
        let sema = try #require(ctx.sema)
        let binding = try #require(delegationBindings(for: "P", sema: sema, interner: ctx.interner).first)
        #expect(binding.parameterMapping == [0: 1])
    }

    @Test(arguments: ["mutableListOf<Nothing>()", "mutableListOf<Int>()", "listOf()"])
    func secondaryDelegationRejectsIncompatibleFactory(argument: String) throws {
        let source = """
        typealias Action<T> = (T) -> Unit
        class P<T>(val actions: MutableList<Action<T>>) {
            constructor() : this(\(argument))
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-TYPE-0001" })
        let sema = try #require(ctx.sema)
        #expect(delegationBindings(for: "P", sema: sema, interner: ctx.interner).isEmpty)
    }

    private func delegationBindings(
        for name: String,
        target: String? = nil,
        sema: SemaModule,
        interner: StringInterner
    ) -> [CallBinding] {
        sema.bindings.constructorDelegationCallBindings.compactMap { constructor, binding in
            guard let owner = sema.symbols.parentSymbol(for: constructor),
                  let symbol = sema.symbols.symbol(owner),
                  interner.resolve(symbol.name) == name,
                  let targetOwner = sema.symbols.parentSymbol(for: binding.chosenCallee),
                  let targetSymbol = sema.symbols.symbol(targetOwner),
                  interner.resolve(targetSymbol.name) == (target ?? name)
            else { return nil }
            return binding
        }
    }

    @Test
    func genericSecondaryDelegationUsesDeclaredOwnerTypeArguments() throws {
        let source = """
        package ksp557

        open class Base<A, B> {
            constructor(capacity: Int)
            constructor(label: String)
        }

        class FromSuper<K, V> : Base<V, K> {
            constructor(capacity: Int) : super(capacity)
            constructor(label: String) : super(label)
        }

        class FromThis<K, V>(capacity: Int) : Base<String, V>(capacity) {
            constructor(capacity: Int, loadFactor: Float) : this(capacity)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Generic delegations should resolve: \(errors)")
        let sema = try #require(ctx.sema)
        let fromSuper = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && ctx.interner.resolve($0.name) == "FromSuper"
        })
        let targets = sema.bindings.constructorDelegationTargets.compactMap { source, target -> SymbolID? in
            sema.symbols.parentSymbol(for: source) == fromSuper.id ? target : nil
        }
        #expect(targets.count == 2)
        #expect(Set(targets).count == 2, "Distinct super(...) overloads must retain distinct targets")
    }

    @Test
    func genericSecondaryDelegationStillRejectsWrongArgumentType() throws {
        let source = """
        package ksp557

        open class Base<K, V> {
            constructor(capacity: Int)
        }

        class Wrong<K, V> : Base<K, V> {
            constructor(label: String) : super(label)
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
        #expect(
            codes.contains("KSWIFTK-SEMA-0002") || codes.contains("KSWIFTK-TYPE-0001"),
            "Wrong super(...) argument should be rejected by overload resolution: \(codes)"
        )
    }

    @Test
    func implicitAnyConstructorDoesNotResolveBareSuperDelegation() throws {
        let source = """
        package ksp805

        class Foo {
            constructor(x: Int) : super()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(
            codes.contains("KSWIFTK-SEMA-0021") || codes.contains("KSWIFTK-SEMA-0055"),
            "Expected an invalid super() diagnostic, got: \(codes)"
        )
    }

    @Test
    func explicitAnyConstructorRemainsAValidDelegationTarget() throws {
        let source = """
        package ksp805

        class Foo : Any() {
            constructor(x: Int) : super()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(
            !codes.contains("KSWIFTK-SEMA-0055"),
            "Explicit Any() should resolve super(), got: \(codes)"
        )
    }
}
#endif
