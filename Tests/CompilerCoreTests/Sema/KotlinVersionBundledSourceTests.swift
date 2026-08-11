#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-610: `KotlinVersion` is bundled Kotlin source; the only native bridge left
/// is the build-time constant `__kk_kotlin_version_current`.
@Suite
struct KotlinVersionBundledSourceTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        let pair = try makeSema()
        Self._sharedSema = pair
        return pair
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKotlinVersionComesFromBundledSourceWithoutLegacyBridges() throws {
        let (sema, interner) = try sharedSema()

        let versionFQName = ["kotlin", "KotlinVersion"].map { interner.intern($0) }
        let versionSymbol = try #require(sema.symbols.lookup(fqName: versionFQName))
        #expect(sema.symbols.symbol(versionSymbol)?.kind == .class)

        let versionType = sema.types.make(.classType(ClassType(
            classSymbol: versionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let comparableFQName = ["kotlin", "Comparable"].map { interner.intern($0) }
        let comparableSymbol = try #require(sema.symbols.lookup(fqName: comparableFQName))
        #expect(sema.symbols.directSupertypes(for: versionSymbol).contains(comparableSymbol))
        #expect(sema.symbols.supertypeTypeArgs(for: versionSymbol, supertype: comparableSymbol) == [.invariant(versionType)])

        for name in ["major", "minor", "patch"] {
            let propertySymbol = try #require(sema.symbols.lookup(fqName: versionFQName + [interner.intern(name)]))
            #expect(sema.symbols.symbol(propertySymbol)?.kind == .property)
            #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.intType)
            #expect(sema.symbols.externalLinkName(for: propertySymbol) == nil)
        }

        let compareToSymbol = try #require(sema.symbols.lookupAll(fqName: versionFQName + [interner.intern("compareTo")]).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [versionType]
        })
        #expect(sema.symbols.functionSignature(for: compareToSymbol)?.returnType == sema.types.intType)
        #expect(sema.symbols.symbol(compareToSymbol)?.flags.contains(.overrideMember) == true)
        #expect(sema.symbols.externalLinkName(for: compareToSymbol) == nil)

        let isAtLeastFQName = versionFQName + [interner.intern("isAtLeast")]
        for parameters in [
            [sema.types.intType, sema.types.intType],
            [sema.types.intType, sema.types.intType, sema.types.intType],
        ] {
            let symbol = try #require(sema.symbols.lookupAll(fqName: isAtLeastFQName).first {
                sema.symbols.functionSignature(for: $0)?.parameterTypes == parameters
            })
            #expect(sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.booleanType)
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        }
    }

    @Test func testKotlinVersionMembersResolveInSource() throws {
        _ = try makeSema(source: """
        fun defaultPatch(): Int = KotlinVersion(2, 1).patch
        fun explicitPatch(): Int = KotlinVersion(2, 1, 20).major
        fun typed(): KotlinVersion = KotlinVersion(1, 9)
        fun currentPatch(): Int = KotlinVersion.CURRENT.patch
        fun rendered(): String = KotlinVersion(2, 1).toString()
        fun compare(): Int = KotlinVersion(2, 1, 20).compareTo(KotlinVersion(2, 1))
        fun hasAtLeast(): Boolean = KotlinVersion.CURRENT.isAtLeast(1, 0) && KotlinVersion(2, 1).isAtLeast(2, 1, 0)
        fun ordered(): Boolean = KotlinVersion(2, 1) < KotlinVersion(2, 1, 20)
        """)
    }
}
#endif
