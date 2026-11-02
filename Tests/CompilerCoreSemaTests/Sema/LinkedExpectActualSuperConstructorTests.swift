#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct LinkedExpectActualSuperConstructorTests {
    @Test(arguments: [false, true])
    func exactIssueReproducerBindsActualConstructor(useLibrary: Bool) throws {
        let ctx = try makeContext([
            """
            package x
            expect open class MIE(m: String) : Exception
            class Sub(m: String) : MIE(m)
            actual open class MIE(m: String) : Exception(m)
            """
        ], useLibrary: useLibrary)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0436" },
            "Expect class supertypes may omit the constructor invocation: \(errors)"
        )
        #expect(errors.isEmpty, "Linked super constructors should not be ambiguous: \(errors)")
        try expectActualDelegation(from: "Sub", to: "MIE", ctx: ctx)
    }

    // KUU-4105: expect objects list supertypes bare — initialization belongs
    // to the actual declaration, so SEMA-0436 must not fire.
    @Test
    func expectObjectSupertypeMayOmitConstructorInvocation() throws {
        let ctx = try makeContext([
            """
            package x
            internal expect object E : RuntimeException
            internal actual object E : RuntimeException()
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0436" },
            "Expect object supertypes may omit the constructor invocation: \(errors)"
        )
        #expect(errors.isEmpty, "expect/actual object pair should link cleanly: \(errors)")
    }

    // Members nested inside an expect declaration are implicitly expect
    // (kotlinc rejects an explicit `expect` modifier there), so a bare class
    // supertype on a nested object or class must not require `()` either.
    @Test
    func nestedMembersOfExpectDeclarationsSkipSupertypeInitialization() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect object OuterObj {
                object Inner : Sup
            }
            expect class OuterClass {
                class Inner : Sup
            }
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0436" },
            "Implicitly expect members may omit the constructor invocation: \(errors)"
        )
    }

    @Test(arguments: ["MIE(m)", "x.MIE(m)", "AliasMIE(m)"])
    func splitSourcesBindActualConstructor(superCall: String) throws {
        let ctx = try makeContext([
            """
            package x
            expect open class MIE(m: String) : Exception
            typealias AliasMIE = MIE
            class Sub(m: String) : \(superCall)
            """,
            """
            package x
            actual open class MIE(m: String) : Exception(m)
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Linked super constructors should resolve through \(superCall): \(errors)")
        try expectActualDelegation(from: "Sub", to: "MIE", ctx: ctx)
    }

    @Test
    func emptyAndGenericSuperCallsKeepActualOverloads() throws {
        let ctx = try makeContext([
            """
            package x
            expect open class Empty()
            expect open class Generic<T>(value: T)
            expect open class Overloaded {
                constructor(value: String)
            }
            class EmptySub : Empty()
            class GenericSub : Generic<String>("value")
            actual open class Empty actual constructor()
            actual open class Generic<T> actual constructor(value: T)
            actual open class Overloaded {
                actual constructor(value: String) {}
                constructor(value: String, marker: Int) {}
            }
            class OverloadedSub : Overloaded("value", 1)
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Filtering by owner must keep actual overloads and type arguments: \(errors)")
        try expectActualDelegation(from: "EmptySub", to: "Empty", ctx: ctx)
        try expectActualDelegation(from: "GenericSub", to: "Generic", ctx: ctx, parameterCount: 1)
        try expectActualDelegation(from: "OverloadedSub", to: "Overloaded", ctx: ctx, parameterCount: 2)
    }

    @Test
    func incompatibleSuperArgumentRemainsRejected() throws {
        let ctx = try makeContext([
            """
            package x
            expect open class MIE(m: String) : Exception
            class Sub : MIE(1)
            actual open class MIE(m: String) : Exception(m)
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "A linked constructor still requires a compatible argument")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0003" })
        let sema = try #require(ctx.sema)
        let constructor = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("x"), ctx.interner.intern("Sub"), ctx.interner.intern("<init>"),
        ]))
        #expect(sema.bindings.constructorDelegationCallBinding(for: constructor) == nil)
    }

    @Test
    func objectSuperCallBindsActualConstructor() throws {
        let ctx = try makeContext([
            """
            package x
            expect open class MIE(m: String) : Exception
            object Sub : MIE("value")
            actual open class MIE(m: String) : Exception(m)
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Object super calls must select actual constructors: \(errors)")
        try expectActualDelegation(from: "Sub", to: "MIE", ctx: ctx)
    }

    @Test(arguments: ["Generic<String>", "AliasGeneric<String>"])
    func secondarySuperCallPreservesActualTypeArguments(supertype: String) throws {
        let ctx = try makeContext([
            """
            package x
            expect open class Generic<T>(value: T)
            typealias AliasGeneric<T> = Generic<T>
            class Sub : \(supertype) {
                constructor(value: String) : super(value) {}
            }
            actual open class Generic<T> actual constructor(value: T) {
                constructor(value: T, marker: Int) : this(value) {}
            }
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Secondary delegation must use actual owners and type arguments: \(errors)")
        try expectActualDelegation(from: "Sub", to: "Generic", ctx: ctx, parameterCount: 1)
        let sema = try #require(ctx.sema)
        let constructor = try #require(sema.symbols.lookup(fqName: [
            ctx.interner.intern("x"), ctx.interner.intern("Sub"), ctx.interner.intern("<init>"),
        ]))
        let binding = try #require(sema.bindings.constructorDelegationCallBinding(for: constructor))
        #expect(binding.substitutedTypeArguments == [sema.types.stringType])
    }

    @Test(arguments: [
        "class Local : Generic<String>(value)",
        "val local = object : Generic<String>(value) {}",
    ])
    func localSuperCallsBindActualWithTypeArguments(declaration: String) throws {
        let ctx = try makeContext([
            """
            package x
            expect open class Generic<T>(value: T)
            actual open class Generic<T> actual constructor(value: T)
            fun use(value: String) {
                \(declaration)
            }
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Local super calls must retain actual owners and type arguments: \(errors)")
        let sema = try #require(ctx.sema)
        let classes = sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("x"), ctx.interner.intern("Generic"),
        ]).compactMap { sema.symbols.symbol($0) }
        let expectClass = try #require(classes.first { $0.flags.contains(.expectDeclaration) })
        let actualClass = try #require(classes.first { $0.flags.contains(.actualDeclaration) })
        let bindings = sema.bindings.constructorDelegationCallBindings.values.filter {
            let owner = sema.symbols.parentSymbol(for: $0.chosenCallee)
            return owner == expectClass.id || owner == actualClass.id
        }
        #expect(bindings.count == 1)
        let binding = try #require(bindings.first)
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == actualClass.id)
        #expect(binding.substitutedTypeArguments == [sema.types.stringType])
    }

    // KUU-4122: expect declarations cannot invoke supertype constructors —
    // initialization belongs to the matching actual declaration. kotlinc
    // reports both "supertype initialization is impossible without a primary
    // constructor" (expect classes/objects without `()` have none) and
    // "'expect' classes cannot initialize supertypes".
    @Test
    func expectClassSupertypeConstructorInvocationIsRejected() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect class Y : Sup()
            actual class Y : Sup()
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "expect class without `()` has no primary constructor: \(errors)"
        )
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0475" },
            "expect class cannot initialize supertypes: \(errors)"
        )
    }

    @Test
    func expectObjectSupertypeConstructorInvocationIsRejected() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect object X : Sup()
            actual object X : Sup()
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "expect object has no primary constructor: \(errors)"
        )
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0475" },
            "expect object cannot initialize supertypes: \(errors)"
        )
    }

    // An expect class with an explicit primary constructor only earns the
    // expect-specific diagnostic — the invocation would be possible for a
    // non-expect class (kotlinc emits no "impossible" error there).
    @Test
    func expectClassWithPrimaryConstructorSkipsImpossibleDiagnostic() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect class A() : Sup()
            actual class A() : Sup()
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "expect class with `()` has a primary constructor: \(errors)"
        )
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0475" },
            "expect class cannot initialize supertypes: \(errors)"
        )
    }

    // The check is purely syntactic: kotlinc reports both diagnostics even
    // when the supertype name fails to resolve.
    @Test
    func expectSupertypeInvocationIsRejectedEvenWhenUnresolved() throws {
        let ctx = try makeContext([
            """
            package x
            expect class Y : Bogus()
            actual class Y
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0474" },
            "Unresolved expect supertype still has no primary constructor: \(errors)"
        )
        #expect(
            errors.contains { $0.code == "KSWIFTK-SEMA-0475" },
            "Unresolved expect supertype still cannot be initialized: \(errors)"
        )
    }

    // Members nested inside an expect declaration are implicitly expect, so
    // their supertype constructor invocations are rejected the same way.
    @Test
    func nestedMembersOfExpectDeclarationsRejectSupertypeInvocation() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect object OuterObj {
                object Inner : Sup()
            }
            actual object OuterObj {
                actual object Inner : Sup()
            }
            expect class OuterClass {
                class Inner : Sup()
            }
            actual class OuterClass {
                actual class Inner : Sup()
            }
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let impossible = errors.filter { $0.code == "KSWIFTK-SEMA-0474" }
        let expectInit = errors.filter { $0.code == "KSWIFTK-SEMA-0475" }
        #expect(impossible.count == 2, "Both implicit-expect inners lack primary constructors: \(errors)")
        #expect(expectInit.count == 2, "Both implicit-expect inners cannot initialize supertypes: \(errors)")
    }

    // Bare supertypes on expect declarations and constructor invocations on
    // non-expect declarations stay legal.
    @Test
    func legalSupertypeFormsDoNotEmitExpectDiagnostics() throws {
        let ctx = try makeContext([
            """
            package x
            open class Sup
            expect class E : Sup
            actual class E : Sup()
            class Z : Sup()
            object W : Sup()
            class NoPrim : Sup {
                constructor(x: Int) : super()
            }
            """
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            !errors.contains { $0.code == "KSWIFTK-SEMA-0474" || $0.code == "KSWIFTK-SEMA-0475" },
            "Legal supertype forms must not emit expect diagnostics: \(errors)"
        )
        #expect(errors.isEmpty, "Legal supertype forms should compile cleanly: \(errors)")
    }

    private func makeContext(_ sources: [String], useLibrary: Bool = true) throws -> CompilationContext {
        let libraryPath: String?
        if useLibrary {
            TestStdlibCache.shared.prepare()
            libraryPath = try #require(CompilerOptions.defaultStdlibLibraryPath)
        } else {
            libraryPath = nil
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = sources.indices.map { directory.appendingPathComponent("input\($0).kt").path }
        // kirDump does not select the default artifact, so pass its path explicitly.
        let ctx = makeCompilationContext(inputs: paths, stdlibLibraryPath: libraryPath)
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        return ctx
    }

    private func expectActualDelegation(
        from subclassName: String,
        to superclassName: String,
        ctx: CompilationContext,
        parameterCount: Int? = nil
    ) throws {
        let sema = try #require(ctx.sema)
        let package = ctx.interner.intern("x")
        let superclassFQName = [package, ctx.interner.intern(superclassName)]
        let classes = sema.symbols.lookupAll(fqName: superclassFQName).compactMap { sema.symbols.symbol($0) }
        let expectClass = try #require(classes.first { $0.flags.contains(.expectDeclaration) })
        let actualClass = try #require(classes.first { $0.flags.contains(.actualDeclaration) })
        #expect(sema.symbols.actualSymbol(for: expectClass.id) == actualClass.id)

        let subclass = try #require(sema.symbols.lookup(fqName: [package, ctx.interner.intern(subclassName)]))
        let constructor: SymbolID
        if sema.symbols.symbol(subclass)?.kind == .object {
            constructor = subclass
        } else {
            constructor = try #require(sema.symbols.lookupAll(fqName: [
                package, ctx.interner.intern(subclassName), ctx.interner.intern("<init>"),
            ]).first { sema.symbols.parentSymbol(for: $0) == subclass })
        }
        let binding = try #require(sema.bindings.constructorDelegationCallBinding(for: constructor))
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == actualClass.id)
        if let parameterCount {
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.parameterTypes.count == parameterCount)
        }
    }
}
#endif
