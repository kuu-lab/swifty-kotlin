#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropNativePlacementSurfaceTests {
    @Test func testNativePlacementInterfaceSurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
                let found = sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) })
            return try #require(found, "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered")
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }
        func cinteropType(_ path: String...) throws -> TypeID {
            sema.types.make(.classType(ClassType(
                classSymbol: try cinteropSymbol(path),
                args: [],
                nullability: .nonNull
            )))
        }

        let nativePlacementSymbol = try cinteropSymbol("NativePlacement")
        let nativePlacementType = try cinteropType("NativePlacement")

        #expect(sema.symbols.symbol(nativePlacementSymbol)?.kind == .interface)
        #expect(sema.symbols.propertyType(for: nativePlacementSymbol) == nativePlacementType)
        #expect(sema.symbols.directSupertypes(for: nativePlacementSymbol) == [])
        #expect(sema.types.directNominalSupertypes(for: nativePlacementSymbol) == [])
    }

    @Test func testNativePlacementAllocMembersAreRegistered() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement alloc members to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let nativePlacementSymbol = try #require(sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "NativePlacement"].map { interner.intern($0) }))
        let nativePointedSymbol = try #require(sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "NativePointed"].map { interner.intern($0) }))
        let nativePlacementType = sema.types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nativePointedType = sema.types.make(.classType(ClassType(
            classSymbol: nativePointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fqName = try #require(sema.symbols.symbol(nativePlacementSymbol)?.fqName)
        let allocMembers = sema.symbols.lookupAll(fqName: fqName + [interner.intern("alloc")])

        let longAlloc = try #require(allocMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes == [sema.types.longType, sema.types.intType]
                && signature.returnType == nativePointedType
        })
        #expect(sema.symbols.symbol(longAlloc)?.flags.contains(.abstractType) == true)

        let intAlloc = try #require(allocMembers.first { symbol in
            guard let signature = sema.symbols.functionSignature(for: symbol) else {
                return false
            }
            return signature.receiverType == nativePlacementType
                && signature.parameterTypes == [sema.types.intType, sema.types.intType]
                && signature.returnType == nativePointedType
        })
        #expect(sema.symbols.symbol(intAlloc)?.flags.contains(.openType) == true)
    }

    @Test func testNativePlacementAllocResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.NativePlacement
        import kotlinx.cinterop.NativePointed

        fun byInt(placement: NativePlacement): NativePointed {
            return placement.alloc(8, 4)
        }

        fun byLong(placement: NativePlacement): NativePointed {
            return placement.alloc(8L, 4)
        }
        """)
        try runSema(ctx)

        #expect(!(ctx.diagnostics.hasError), "Expected NativePlacement.alloc to resolve, got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
