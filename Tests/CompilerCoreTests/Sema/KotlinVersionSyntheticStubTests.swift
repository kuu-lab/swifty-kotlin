#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct KotlinVersionSyntheticStubTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    @Test func testKotlinVersionConstructorsAndPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let versionFQName = ["kotlin", "KotlinVersion"].map { interner.intern($0) }
        let versionSymbol = try #require(sema.symbols.lookup(fqName: versionFQName))
        #expect(sema.symbols.symbol(versionSymbol)?.kind == .class)

        let versionType = sema.types.make(.classType(ClassType(
            classSymbol: versionSymbol,
            args: [],
            nullability: .nonNull
        )))

        let constructorFQName = versionFQName + [interner.intern("<init>")]
        let constructors = sema.symbols.lookupAll(fqName: constructorFQName).filter {
            sema.symbols.symbol($0)?.kind == .constructor
        }
        let twoArgumentConstructor = try #require(constructors.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType, sema.types.intType]
        })
        #expect(sema.symbols.externalLinkName(for: twoArgumentConstructor) == "kk_kotlin_version_new")
        #expect(sema.symbols.functionSignature(for: twoArgumentConstructor)?.returnType == versionType)

        let threeArgumentConstructor = try #require(constructors.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
        })
        #expect(sema.symbols.externalLinkName(for: threeArgumentConstructor) == "kk_kotlin_version_new_patch")
        #expect(sema.symbols.functionSignature(for: threeArgumentConstructor)?.returnType == versionType)

        let comparableFQName = ["kotlin", "Comparable"].map { interner.intern($0) }
        let comparableSymbol = try #require(sema.symbols.lookup(fqName: comparableFQName))
        let versionExtendsComparable = sema.symbols.directSupertypes(for: versionSymbol).contains(comparableSymbol)
        #expect(versionExtendsComparable)
        #expect(sema.symbols.supertypeTypeArgs(for: versionSymbol, supertype: comparableSymbol) == [.in(versionType)])

        let expectedProperties: [(name: String, link: String)] = [
            ("major", "kk_kotlin_version_major"),
            ("minor", "kk_kotlin_version_minor"),
            ("patch", "kk_kotlin_version_patch"),
        ]
        for expected in expectedProperties {
            let propertySymbol = try #require(sema.symbols.lookup(fqName: versionFQName + [interner.intern(expected.name)]))
            #expect(sema.symbols.symbol(propertySymbol)?.kind == .property)
            #expect(sema.symbols.parentSymbol(for: propertySymbol) == versionSymbol)
            #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.intType)
            #expect(sema.symbols.externalLinkName(for: propertySymbol) == expected.link)
        }

        let companionFQName = versionFQName + [interner.intern("Companion")]
        let companionSymbol = try #require(sema.symbols.lookup(fqName: companionFQName))
        #expect(sema.symbols.companionObjectSymbol(for: versionSymbol) == companionSymbol)

        let currentSymbol = try #require(sema.symbols.lookup(fqName: companionFQName + [interner.intern("CURRENT")]))
        #expect(sema.symbols.symbol(currentSymbol)?.kind == .property)
        #expect(sema.symbols.parentSymbol(for: currentSymbol) == companionSymbol)
        #expect(sema.symbols.propertyType(for: currentSymbol) == versionType)
        #expect(sema.symbols.externalLinkName(for: currentSymbol) == "kk_kotlin_version_current")
        #expect(sema.symbols.symbol(currentSymbol)?.flags.contains(.static) == true)

        let compareToSymbol = try #require(sema.symbols.lookupAll(fqName: versionFQName + [interner.intern("compareTo")]).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [versionType]
        })
        #expect(sema.symbols.functionSignature(for: compareToSymbol)?.receiverType == versionType)
        #expect(sema.symbols.functionSignature(for: compareToSymbol)?.returnType == sema.types.intType)
        #expect(sema.symbols.externalLinkName(for: compareToSymbol) == "kk_kotlin_version_compareTo")
        #expect(sema.symbols.symbol(compareToSymbol)?.flags.contains(.operatorFunction) == true)

        let isAtLeastFQName = versionFQName + [interner.intern("isAtLeast")]
        let twoArgumentIsAtLeast = try #require(sema.symbols.lookupAll(fqName: isAtLeastFQName).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [sema.types.intType, sema.types.intType]
        })
        #expect(sema.symbols.functionSignature(for: twoArgumentIsAtLeast)?.receiverType == versionType)
        #expect(sema.symbols.functionSignature(for: twoArgumentIsAtLeast)?.returnType == sema.types.booleanType)
        #expect(sema.symbols.externalLinkName(for: twoArgumentIsAtLeast) == "kk_kotlin_version_isAtLeast")

        let threeArgumentIsAtLeast = try #require(sema.symbols.lookupAll(fqName: isAtLeastFQName).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes == [
                sema.types.intType,
                sema.types.intType,
                sema.types.intType,
            ]
        })
        #expect(sema.symbols.functionSignature(for: threeArgumentIsAtLeast)?.receiverType == versionType)
        #expect(sema.symbols.functionSignature(for: threeArgumentIsAtLeast)?.returnType == sema.types.booleanType)
        #expect(sema.symbols.externalLinkName(for: threeArgumentIsAtLeast) == "kk_kotlin_version_isAtLeast_patch")
    }

    @Test func testKotlinVersionConstructorsAndPropertiesResolveInSource() throws {
        _ = try makeSema(source: """
        fun defaultPatch(): Int = KotlinVersion(2, 1).patch
        fun explicitPatch(): Int = KotlinVersion(2, 1, 20).major
        fun typed(): KotlinVersion = KotlinVersion(1, 9)
        fun currentPatch(): Int = KotlinVersion.CURRENT.patch
        fun compare(): Int = KotlinVersion(2, 1, 20).compareTo(KotlinVersion(2, 1))
        fun hasAtLeast(): Boolean = KotlinVersion.CURRENT.isAtLeast(1, 0) && KotlinVersion(2, 1).isAtLeast(2, 1, 0)
        fun ordered(): Boolean = KotlinVersion(2, 1) < KotlinVersion(2, 1, 20)
        """)
    }
}
#endif
