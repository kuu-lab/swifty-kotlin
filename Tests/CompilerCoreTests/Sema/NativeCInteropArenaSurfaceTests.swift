#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private struct _TestHelperFailure: Error {}

@Suite
struct NativeCInteropArenaSurfaceTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(
                !(ctx.diagnostics.hasError),
                "Expected C interop Arena surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func symbol(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
            let found = sema.symbols.lookup(fqName: fqPath.map { interner.intern($0) })
        return try #require(found, "\(fqPath.joined(separator: ".")) must be registered")
    }

    private func classType(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let classSymbol = try symbol(fqPath, sema: sema, interner: interner, file: file, line: line)
        return sema.types.make(.classType(ClassType(
            classSymbol: classSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func arenaMemberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner, file: file, line: line)
        let ownerFQName = try #require(sema.symbols.symbol(arenaSymbol)?.fqName)
        let receiver = try classType(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner, file: file, line: line)
        let candidates = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern(name)])
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == receiver
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        Issue.record("Expected Arena.\(name) signature, got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })")
        throw _TestHelperFailure()
    }

    @Test func testArenaClassAndRequiredSupportSymbolsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let arenaBaseSymbol = try symbol(["kotlinx", "cinterop", "ArenaBase"], sema: sema, interner: interner)
        let nativeFreeablePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let nativePlacementSymbol = try symbol(["kotlinx", "cinterop", "NativePlacement"], sema: sema, interner: interner)

        #expect(sema.symbols.symbol(arenaSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(arenaBaseSymbol)?.kind == .class)
        #expect(sema.symbols.symbol(nativeFreeablePlacementSymbol)?.kind == .interface)
        #expect(sema.symbols.directSupertypes(for: arenaSymbol) == [arenaBaseSymbol])
        #expect(sema.symbols.directSupertypes(for: nativeFreeablePlacementSymbol) == [nativePlacementSymbol])
    }

    @Test func testArenaConstructorUsesNativeFreeablePlacementDefault() throws {
        let (sema, interner) = try makeSema()
        let arenaSymbol = try symbol(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let arenaFQName = try #require(sema.symbols.symbol(arenaSymbol)?.fqName)
        let arenaType = try classType(["kotlinx", "cinterop", "Arena"], sema: sema, interner: interner)
        let parentType = try classType(["kotlinx", "cinterop", "NativeFreeablePlacement"], sema: sema, interner: interner)
        let constructors = sema.symbols.lookupAll(fqName: arenaFQName + [interner.intern("<init>")])

        let signature = try #require(constructors.compactMap { sema.symbols.functionSignature(for: $0) }.first {
            $0.parameterTypes == [parentType] && $0.returnType == arenaType
        })
        #expect(signature.valueParameterHasDefaultValues == [true])
    }

    @Test func testArenaAllocOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let nativePointedType = try classType(["kotlinx", "cinterop", "NativePointed"], sema: sema, interner: interner)

        let (longAlloc, _) = try arenaMemberSignature(
            named: "alloc",
            parameters: [sema.types.longType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.symbol(longAlloc)?.flags.contains(.overrideMember) == true)

        let (intAlloc, _) = try arenaMemberSignature(
            named: "alloc",
            parameters: [sema.types.intType, sema.types.intType],
            returnType: nativePointedType,
            sema: sema,
            interner: interner
        )
        #expect(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    @Test func testArenaResolvesInSource() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.Arena
        import kotlinx.cinterop.NativePointed

        fun probe(): NativePointed {
            val arena = Arena()
            return arena.alloc(8, 4)
        }
        """)
    }
}
#endif
