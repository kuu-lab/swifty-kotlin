#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RangeRandomSyntheticLinkTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try #require(result)
    }

    private func assertRandomOrNullOverloads(
        typeName: String,
        noArgLink: String,
        randomLink: String,
        expectedElementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        randomSymbol: SymbolID
    ) {
        let fq = ["kotlin", "ranges", typeName, "randomOrNull"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)
        #expect(!(symbols.isEmpty), Comment(rawValue: "\(typeName).randomOrNull must be registered"))

        let noArg = symbols.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }
        #expect(noArg != nil, Comment(rawValue: "\(typeName).randomOrNull() overload missing"))
        if let noArg {
            #expect(sema.symbols.externalLinkName(for: noArg) == noArgLink)
            guard let sig = sema.symbols.functionSignature(for: noArg) else {
                Issue.record(Comment(rawValue: "\(typeName).randomOrNull() has no signature"))
                return
            }
            #expect(sig.returnType == sema.types.makeNullable(expectedElementType))
        }

        let seeded = symbols.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 1
        }
        #expect(seeded != nil, Comment(rawValue: "\(typeName).randomOrNull(random: Random) overload missing"))
        if let seeded {
            #expect(sema.symbols.externalLinkName(for: seeded) == randomLink)
            guard let sig = sema.symbols.functionSignature(for: seeded) else {
                Issue.record(Comment(rawValue: "\(typeName).randomOrNull(random: Random) has no signature"))
                return
            }
            #expect(sig.returnType == sema.types.makeNullable(expectedElementType))
            guard case .classType(let classType) = sema.types.kind(of: sig.parameterTypes[0]) else {
                Issue.record(Comment(rawValue: "\(typeName).randomOrNull(random: Random) parameter is not a class type"))
                return
            }
            #expect(
                classType.classSymbol == randomSymbol,
                Comment(rawValue: "\(typeName).randomOrNull(random: Random) must take kotlin.random.Random")
            )
        }
    }

    private func assertRandomOverloads(
        typeName: String,
        noArgLink: String,
        randomLink: String,
        expectedElementType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        randomSymbol: SymbolID
    ) {
        let fq = ["kotlin", "ranges", typeName, "random"].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)
        #expect(!(symbols.isEmpty), Comment(rawValue: "\(typeName).random must be registered"))

        let noArg = symbols.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        }
        #expect(noArg != nil, Comment(rawValue: "\(typeName).random() overload missing"))
        if let noArg {
            #expect(sema.symbols.externalLinkName(for: noArg) == noArgLink)
            #expect(sema.symbols.functionSignature(for: noArg)?.returnType == expectedElementType)
        }

        let seeded = symbols.first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.count == 1
        }
        #expect(seeded != nil, Comment(rawValue: "\(typeName).random(random: Random) overload missing"))
        if let seeded {
            #expect(sema.symbols.externalLinkName(for: seeded) == randomLink)
            guard let sig = sema.symbols.functionSignature(for: seeded) else {
                Issue.record(Comment(rawValue: "\(typeName).random(random: Random) has no signature"))
                return
            }
            #expect(sig.returnType == expectedElementType)
            guard case .classType(let classType) = sema.types.kind(of: sig.parameterTypes[0]) else {
                Issue.record(Comment(rawValue: "\(typeName).random(random: Random) parameter is not a class type"))
                return
            }
            #expect(
                classType.classSymbol == randomSymbol,
                Comment(rawValue: "\(typeName).random(random: Random) must take kotlin.random.Random")
            )
        }
    }

    @Test func testRangeRandomOrNullOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(
            sema.symbols.lookup(fqName: randomFQ),
            "kotlin.random.Random must be registered"
        )

        assertRandomOrNullOverloads(
            typeName: "IntRange",
            noArgLink: "kk_range_randomOrNull",
            randomLink: "kk_range_randomOrNull_random",
            expectedElementType: sema.types.intType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOrNullOverloads(
            typeName: "LongRange",
            noArgLink: "kk_long_range_randomOrNull",
            randomLink: "kk_long_range_randomOrNull_random",
            expectedElementType: sema.types.longType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOrNullOverloads(
            typeName: "UIntRange",
            noArgLink: "kk_uint_range_randomOrNull",
            randomLink: "kk_uint_range_randomOrNull_random",
            expectedElementType: sema.types.uintType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOrNullOverloads(
            typeName: "ULongRange",
            noArgLink: "kk_ulong_range_randomOrNull",
            randomLink: "kk_ulong_range_randomOrNull_random",
            expectedElementType: sema.types.ulongType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOrNullOverloads(
            typeName: "CharRange",
            noArgLink: "kk_char_range_randomOrNull",
            randomLink: "kk_char_range_randomOrNull_random",
            expectedElementType: sema.types.charType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
    }

    @Test func testRangeRandomOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(
            sema.symbols.lookup(fqName: randomFQ),
            "kotlin.random.Random must be registered"
        )

        assertRandomOverloads(
            typeName: "IntRange",
            noArgLink: "kk_range_random",
            randomLink: "kk_range_random_random",
            expectedElementType: sema.types.intType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOverloads(
            typeName: "LongRange",
            noArgLink: "kk_long_range_random",
            randomLink: "kk_long_range_random_random",
            expectedElementType: sema.types.longType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOverloads(
            typeName: "UIntRange",
            noArgLink: "kk_uint_range_random",
            randomLink: "kk_uint_range_random_random",
            expectedElementType: sema.types.uintType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOverloads(
            typeName: "ULongRange",
            noArgLink: "kk_ulong_range_random",
            randomLink: "kk_ulong_range_random_random",
            expectedElementType: sema.types.ulongType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
        assertRandomOverloads(
            typeName: "CharRange",
            noArgLink: "kk_range_random",
            randomLink: "kk_char_range_random_random",
            expectedElementType: sema.types.charType,
            sema: sema,
            interner: interner,
            randomSymbol: randomSymbol
        )
    }
}
#endif
