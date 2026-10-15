#if canImport(Testing)
import CompilerCore
@testable import CompilerTestSupport
import Foundation
import TestStdlibCache
import Testing

@Suite
struct LocalClassSecondarySuperConstructorTests {
    @Test(arguments: [false, true])
    func exactIssueReproducerBindsTheLocalSuperConstructor(useLibrary: Bool) throws {
        let ctx = try makeContext(
            """
            open class C(val value: String)
            fun box(): String {
                class B : C {
                    constructor(x: Int) : super("OK")
                }
                return B(1).value
            }
            """,
            useLibrary: useLibrary
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Local secondary super delegation should resolve: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0055" })

        let sema = try #require(ctx.sema)
        let superclass = try classSymbol(named: "C", sema: sema, interner: ctx.interner)
        let localClass = try classSymbol(named: "B", sema: sema, interner: ctx.interner)
        let constructor = try #require(constructors(of: localClass, sema: sema, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.constructorDelegationCallBinding(for: constructor))
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == superclass)
    }

    @Test(arguments: [false, true])
    func localOverloadsCapturesVisibilityAndDerivedDelegation(useLibrary: Bool) throws {
        let ctx = try makeContext(
            """
            open class C(val value: String) {
                protected constructor(value: String, marker: Int) : this(value)
            }
            open class GenericBase<T>(val value: T)
            class TopLevel : C {
                constructor(value: String) : super(value)
            }
            fun box(): String {
                val captured = "OK"
                class LocalPrimary : C(captured)
                open class LocalBase : C {
                    constructor(marker: Int) : super(captured, marker)
                    constructor(value: String) : super(value)
                    constructor() : this(0)
                }
                class LocalDerived : LocalBase {
                    constructor() : super(0)
                }
                class LocalGeneric : GenericBase<String> {
                    constructor() : super(captured)
                }
                return LocalDerived().value + LocalGeneric().value + LocalPrimary().value
            }
            """,
            useLibrary: useLibrary
        )
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Local secondary super cases should resolve: \(errors)")

        let sema = try #require(ctx.sema)
        let c = try classSymbol(named: "C", sema: sema, interner: ctx.interner)
        let localBase = try classSymbol(named: "LocalBase", sema: sema, interner: ctx.interner)
        let baseConstructors = constructors(of: localBase, sema: sema, interner: ctx.interner)
        #expect(baseConstructors.count == 3)
        let baseTargets = baseConstructors.compactMap {
            sema.bindings.constructorDelegationCallBinding(for: $0)?.chosenCallee
        }.compactMap { sema.symbols.parentSymbol(for: $0) }
        #expect(baseTargets.filter { $0 == c }.count == 2)
        #expect(baseTargets.filter { $0 == localBase }.count == 1)

        let localDerived = try classSymbol(named: "LocalDerived", sema: sema, interner: ctx.interner)
        let derivedConstructor = try #require(
            constructors(of: localDerived, sema: sema, interner: ctx.interner).first
        )
        let derivedBinding = try #require(
            sema.bindings.constructorDelegationCallBinding(for: derivedConstructor)
        )
        #expect(sema.symbols.parentSymbol(for: derivedBinding.chosenCallee) == localBase)

        let genericBase = try classSymbol(named: "GenericBase", sema: sema, interner: ctx.interner)
        let localGeneric = try classSymbol(named: "LocalGeneric", sema: sema, interner: ctx.interner)
        let genericConstructor = try #require(
            constructors(of: localGeneric, sema: sema, interner: ctx.interner).first
        )
        let genericBinding = try #require(
            sema.bindings.constructorDelegationCallBinding(for: genericConstructor)
        )
        #expect(sema.symbols.parentSymbol(for: genericBinding.chosenCallee) == genericBase)
        #expect(genericBinding.substitutedTypeArguments == [sema.types.stringType])
    }

    private func makeContext(_ source: String, useLibrary: Bool) throws -> CompilationContext {
        if useLibrary {
            TestStdlibCache.shared.prepare()
        }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            stdlibLibraryPath: useLibrary ? CompilerOptions.defaultStdlibLibraryPath : nil
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func classSymbol(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> SymbolID {
        try #require(sema.symbols.symbols(ofKind: .class).first { symbol in
            sema.symbols.symbol(symbol).map { interner.resolve($0.name) == name } ?? false
        })
    }

    private func constructors(
        of owner: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let symbol = sema.symbols.symbol(owner) else { return [] }
        return sema.symbols.lookupAll(fqName: symbol.fqName + [interner.intern("<init>")]).filter {
            sema.symbols.parentSymbol(for: $0) == owner
        }
    }
}
#endif
