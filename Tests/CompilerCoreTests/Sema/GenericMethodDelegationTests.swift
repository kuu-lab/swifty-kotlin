#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite struct GenericMethodDelegationTests {
    private func makeContext(_ source: String) -> CompilationContext {
        let path = "/tmp/generic-method-delegation.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func concreteAndInterfaceCallsInferMethodParameters() throws {
        let ctx = makeContext("""
        interface Echo { fun <T> echo(value: T): T }
        class EchoImpl : Echo { override fun <T> echo(value: T): T = value }
        class Delegate(base: Echo) : Echo by base
        fun main() { val result: Int = Delegate(EchoImpl()).echo(7) }
        fun check(concrete: Delegate, throughInterface: Echo) {
            val number: Int = concrete.echo(7)
            val text: String = concrete.echo<String>("text")
            val control: Int = throughInterface.echo(7)
            val anonymous = object : Echo by throughInterface {}
            val anonymousText: String = anonymous.echo("anonymous")
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test func forwardersOwnFreshBindersAndSubstituteAllBounds() throws {
        let ctx = makeContext("""
        interface First
        interface Second
        interface Parent<C> {
            fun <T : C, U : T> choose(value: U): T
            fun <T> transform(values: List<T>, operation: (T) -> T): List<T>
            fun <T> both(value: T): T where T : First, T : Second
            fun <T : Comparable<T>> comparable(value: T): T
        }
        interface Child<C> : Parent<C>
        class Delegate<C : CharSequence>(base: Child<C>) : Child<C> by base
        class Concrete(base: Child<CharSequence>) : Child<CharSequence> by base
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for name in ["Delegate", "Concrete"] {
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(name)]))
            let forwarders = sema.symbols.classDelegationForwardingMethodSymbols(forClass: owner)
            #expect(forwarders.count == 4)
            let classParameters = sema.types.nominalTypeParameterSymbols(for: owner)
            for forwarder in forwarders {
                let info = try #require(sema.symbols.classDelegationForwardingMethodInfo(for: forwarder))
                let original = try #require(sema.symbols.functionSignature(for: info.interfaceMethodSymbol))
                let signature = try #require(sema.symbols.functionSignature(for: forwarder))
                let originalParameters = Array(original.typeParameterSymbols.dropFirst(original.classTypeParameterCount))
                let methodParameters = Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount))
                #expect(signature.classTypeParameterCount == classParameters.count)
                #expect(Array(signature.typeParameterSymbols.prefix(classParameters.count)) == classParameters)
                #expect(Array(signature.typeParameterUpperBoundsList.prefix(classParameters.count))
                    == classParameters.map { sema.symbols.typeParameterUpperBounds(for: $0) })
                #expect(methodParameters.count == originalParameters.count)
                #expect(Set(methodParameters).isDisjoint(with: originalParameters))
                #expect(methodParameters.allSatisfy { sema.symbols.parentSymbol(for: $0) == forwarder })

                let originalClassParameters = Array(original.typeParameterSymbols.prefix(original.classTypeParameterCount))
                let allOriginalParameters = originalClassParameters + originalParameters
                let typeVars = sema.types.makeTypeVarBySymbol(allOriginalParameters)
                let classArgument = try #require(name == "Delegate"
                    ? classParameters.first.map { sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))) }
                    : sema.symbols.lookup(fqName: ["kotlin", "CharSequence"].map { ctx.interner.intern($0) }).map {
                        sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
                    })
                var substitution: [TypeVarID: TypeID] = [:]
                for parameter in originalClassParameters {
                    substitution[try #require(typeVars[parameter])] = classArgument
                }
                for (old, new) in zip(originalParameters, methodParameters) {
                    substitution[try #require(typeVars[old])] = sema.types.make(.typeParam(TypeParamType(
                        symbol: new, nullability: .nonNull
                    )))
                }
                func substitute(_ type: TypeID) -> TypeID {
                    sema.types.substituteTypeParameters(in: type, substitution: substitution, typeVarBySymbol: typeVars)
                }
                #expect(signature.parameterTypes == original.parameterTypes.map(substitute))
                #expect(signature.returnType == substitute(original.returnType))
                let bounds = Array(original.typeParameterUpperBoundsList.dropFirst(original.classTypeParameterCount))
                    .map { $0.map(substitute) }
                #expect(Array(signature.typeParameterUpperBoundsList.dropFirst(signature.classTypeParameterCount)) == bounds)
                #expect(methodParameters.map { sema.symbols.typeParameterUpperBounds(for: $0) } == bounds)
            }
        }
    }

    @Test(arguments: [false, true])
    func dispatchDistinguishesMethodBindersFromReceiverBinders(genericFirst: Bool) throws {
        let generic = "override fun <T> echo(value: T): T = value"
        let concrete = "override fun echo(value: String): String = value"
        let ctx = makeContext("""
        interface Contract<C> {
            fun <T> echo(value: T): T
            fun echo(value: String): String
        }
        class Impl<C> : Contract<C> {
            \(genericFirst ? generic : concrete)
            \(genericFirst ? concrete : generic)
        }
        class Delegate<C>(base: Contract<C>) : Contract<C> by base
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let contract = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Contract")]))
        let methods = sema.symbols.lookupAll(fqName: ["Contract", "echo"].map { ctx.interner.intern($0) })
        #expect(methods.count == 2)
        for ownerName in ["Impl", "Delegate"] {
            let owner = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern(ownerName)]))
            let implementations = sema.symbols.lookupAll(fqName: [ownerName, "echo"].map { ctx.interner.intern($0) })
            for method in methods {
                #expect(sema.symbols.parentSymbol(for: method) == contract)
                let signature = try #require(sema.symbols.functionSignature(for: method))
                let methodArity = signature.typeParameterSymbols.count - signature.classTypeParameterCount
                let expected = try #require(implementations.first {
                    guard let signature = sema.symbols.functionSignature(for: $0) else { return false }
                    return signature.typeParameterSymbols.count - signature.classTypeParameterCount == methodArity
                })
                #expect(kirFindOverrideMethod(for: method, in: owner, sema: sema, interner: ctx.interner) == expected)
            }
        }
    }

    @Test(arguments: ["concrete", "throughInterface"], [
        "bounded(7)", "bounded<Int>(7)", "choose(7)", "choose<Int>(7)",
        "both(OnlyFirst())", "second<CharSequence, Int>(\"first\", 7)"
    ])
    func invalidUpperBoundsRemainRejected(receiver: String, call: String) throws {
        let ctx = makeContext("""
        interface First
        interface Second
        class OnlyFirst : First
        interface Contract<C> {
            fun <T : CharSequence> bounded(value: T): T
            fun <T : C> choose(value: T): T
            fun <T> both(value: T): T where T : First, T : Second
            fun <A, B : A> second(first: A, value: B): B
        }
        class Delegate<C>(base: Contract<C>) : Contract<C> by base
        fun check(concrete: Delegate<CharSequence>, throughInterface: Contract<CharSequence>) {
            \(receiver).\(call)
        }
        """)
        try runSema(ctx)
        let diagnostic = call.hasPrefix("bounded") || call.hasPrefix("both")
            ? "KSWIFTK-SEMA-BOUND" : "KSWIFTK-TYPE-0001"
        assertHasDiagnostic(diagnostic, in: ctx)
    }

}
#endif
