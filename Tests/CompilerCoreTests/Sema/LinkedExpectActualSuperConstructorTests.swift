#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

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
