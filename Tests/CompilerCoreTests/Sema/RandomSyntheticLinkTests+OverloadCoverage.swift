/// Sema overload-resolution coverage for kotlin.random.Random
/// Task: STDLIB-RANDOM-001 (API list) + STDLIB-RANDOM-002 (sema/lowering)
///
/// Each test verifies a specific overload-selection or stub-presence property.
/// Tests marked "// GAP:" document capabilities that are not yet registered
/// in the synthetic stub table and will fail until implemented.

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension RandomSyntheticLinkTests {

    // MARK: - Random factory / seed constructors

    /// Random(seed: Int) factory constructor is registered and linked correctly.
    @Test func testRandomIntSeedConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let ctorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: ctorFQ)
        #expect(!ctors.isEmpty, "Random <init> constructor must be registered")

        let intSeedCtor = ctors.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType
        }
        #expect(intSeedCtor != nil, "Random(seed: Int) constructor must exist")

        if let ctor = intSeedCtor {
            let link = sema.symbols.externalLinkName(for: ctor)
            #expect(link == "kk_random_create_seeded",
                    "Random(seed: Int) must link to kk_random_create_seeded")
        }
    }

    /// Random(seed: Long) factory constructor is registered and linked correctly.
    @Test func testRandomLongSeedConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let ctorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: ctorFQ)

        let longSeedCtor = ctors.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.longType
        }
        #expect(longSeedCtor != nil, "Random(seed: Long) constructor must exist")

        if let ctor = longSeedCtor {
            let link = sema.symbols.externalLinkName(for: ctor)
            #expect(link == "kk_random_create_seeded",
                    "Random(seed: Long) must link to kk_random_create_seeded")
        }
    }

    // MARK: - Random.Default singleton

    /// Random.Default property is registered as the default Random singleton.
    @Test func testRandomDefaultSingletonIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let defaultFQ = ["kotlin", "random", "Random", "Default"].map { interner.intern($0) }
        let defaultSym = sema.symbols.lookup(fqName: defaultFQ)
        #expect(defaultSym != nil, "Random.Default singleton must be registered")

        if let defaultSym {
            let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
            let randomSym = sema.symbols.lookup(fqName: randomFQ)
            #expect(randomSym != nil, "Random object must be registered")
            if let randomSym {
                let expectedType = sema.types.make(.classType(ClassType(
                    classSymbol: randomSym,
                    args: [],
                    nullability: .nonNull
                )))
                #expect(sema.symbols.propertyType(for: defaultSym) == expectedType)
            }
            #expect(sema.symbols.externalLinkName(for: defaultSym) == "kk_random_default")
        }
    }

    // MARK: - nextInt overload selection

    /// nextInt() zero-arg, nextInt(until), and nextInt(from, until) are all registered.
    @Test func testNextIntAllThreeOverloadsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arities = candidates.compactMap { id -> Int? in
            sema.symbols.functionSignature(for: id).map { $0.parameterTypes.count }
        }
        #expect(arities.contains(0), "nextInt() (arity 0) must be registered")
        #expect(arities.contains(1), "nextInt(until) (arity 1) must be registered")
        #expect(arities.contains(2), "nextInt(from, until) (arity 2) must be registered")
    }

    /// nextInt(until) resolves to the arity-1 overload linked to kk_random_nextInt_until.
    @Test func testNextIntUntilOverloadLinksCorrectly() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity1 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.count == 1
        }
        #expect(arity1 != nil, "nextInt(until) overload must exist")
        if let sym = arity1 {
            #expect(sema.symbols.externalLinkName(for: sym) == "kk_random_nextInt_until")
        }
    }

    /// nextInt(from, until) resolves to the arity-2 overload linked to kk_random_nextInt_range.
    @Test func testNextIntFromUntilOverloadLinksCorrectly() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity2 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.count == 2
        }
        #expect(arity2 != nil, "nextInt(from, until) overload must exist")
        if let sym = arity2 {
            #expect(sema.symbols.externalLinkName(for: sym) == "kk_random_nextInt_range")
        }
    }

    /// nextLong(range: LongRange) extension-style overload is registered on Random.
    @Test func testNextLongLongRangeExtensionIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextLong"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let longRangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1,
                  let paramType = sig.parameterTypes.first
            else { return false }
            if case .primitive = sema.types.kind(of: paramType) { return false }
            return true
        }
        #expect(longRangeOverload != nil, "nextLong(range: LongRange) overload must be registered")
        if let longRangeOverload,
           let signature = sema.symbols.functionSignature(for: longRangeOverload)
        {
            #expect(sema.symbols.externalLinkName(for: longRangeOverload) == "kk_random_nextLong_rangeObject")
            #expect(signature.returnType == sema.types.longType)
            #expect(signature.canThrow, "nextLong(range) must expose the empty-range throw path")
        }
    }

    /// nextInt(from, until) and nextInt(until) are distinct symbols (no collision).
    @Test func testNextIntOverloadsAreDistinct() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let links = candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
        #expect(links.contains("kk_random_nextInt_until"),
                "nextInt(until) link must be present")
        #expect(links.contains("kk_random_nextInt_range"),
                "nextInt(from, until) link must be present")
        let untilSym = candidates.first { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_until" }
        let rangeSym = candidates.first { sema.symbols.externalLinkName(for: $0) == "kk_random_nextInt_range" }
        #expect(untilSym != rangeSym,
                "nextInt(until) and nextInt(from, until) must be separate symbols")
    }

    @Test func testNextULongOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextULong"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let ulongRangeFQ = ["kotlin", "ranges", "ULongRange"].map { interner.intern($0) }
        let ulongRangeSymbol = try #require(sema.symbols.lookup(fqName: ulongRangeFQ))
        let ulongRangeType = sema.types.make(.classType(ClassType(
            classSymbol: ulongRangeSymbol,
            args: [],
            nullability: .nonNull
        )))

        func candidate(parameterTypes: [TypeID]) -> SymbolID? {
            candidates.first { id in
                sema.symbols.functionSignature(for: id)?.parameterTypes == parameterTypes
            }
        }

        let zero = try #require(candidate(parameterTypes: []))
        #expect(sema.symbols.externalLinkName(for: zero) == "kk_random_nextULong")

        let until = try #require(candidate(parameterTypes: [sema.types.ulongType]))
        #expect(sema.symbols.externalLinkName(for: until) == "kk_random_nextULong_until")
        #expect(sema.symbols.functionSignature(for: until)?.returnType == sema.types.ulongType)
        #expect(sema.symbols.functionSignature(for: until)?.canThrow ?? false)

        let range = try #require(candidate(parameterTypes: [sema.types.ulongType, sema.types.ulongType]))
        #expect(sema.symbols.externalLinkName(for: range) == "kk_random_nextULong_range")
        #expect(sema.symbols.functionSignature(for: range)?.returnType == sema.types.ulongType)
        #expect(sema.symbols.functionSignature(for: range)?.canThrow ?? false)

        let ulongRange = try #require(candidate(parameterTypes: [ulongRangeType]))
        #expect(sema.symbols.externalLinkName(for: ulongRange) == "kk_random_nextULong_ulongRange")
        #expect(sema.symbols.functionSignature(for: ulongRange)?.returnType == sema.types.ulongType)
        #expect(sema.symbols.functionSignature(for: ulongRange)?.canThrow ?? false)
    }

    // MARK: - nextUInt overload selection

    /// nextUInt() / nextUInt(until) / nextUInt(from, until) / nextUInt(range) are registered.
    @Test func testNextUIntOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextUInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        func isUIntRange(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else { return false }
            return interner.resolve(symbol.name) == "UIntRange"
        }

        let zero = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty == true
        }
        let until = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.uintType]
        }
        let fromUntil = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.uintType, sema.types.uintType]
        }
        let range = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1
            else { return false }
            return isUIntRange(sig.parameterTypes[0])
        }

        #expect(zero != nil, "nextUInt() must be registered")
        #expect(until != nil, "nextUInt(until: UInt) must be registered")
        #expect(fromUntil != nil, "nextUInt(from: UInt, until: UInt) must be registered")
        #expect(range != nil, "nextUInt(range: UIntRange) must be registered")
        if let zero {
            #expect(sema.symbols.externalLinkName(for: zero) == "kk_random_nextUInt")
        }
        if let until,
           let signature = sema.symbols.functionSignature(for: until)
        {
            #expect(sema.symbols.externalLinkName(for: until) == "kk_random_nextUInt_until")
            #expect(signature.canThrow)
        }
        if let fromUntil,
           let signature = sema.symbols.functionSignature(for: fromUntil)
        {
            #expect(sema.symbols.externalLinkName(for: fromUntil) == "kk_random_nextUInt_range")
            #expect(signature.canThrow)
        }
        if let range,
           let signature = sema.symbols.functionSignature(for: range)
        {
            #expect(sema.symbols.externalLinkName(for: range) == "kk_random_nextUInt_uintRange")
            #expect(signature.canThrow)
        }
    }

    // MARK: - nextBytes overloads

    /// nextBytes(array: ByteArray) is registered and linked to kk_random_nextBytes.
    @Test func testNextBytesByteArrayOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        #expect(!candidates.isEmpty, "nextBytes stub must be registered")

        let links = candidates.compactMap { sema.symbols.externalLinkName(for: $0) }
        #expect(links.contains("kk_random_nextBytes"),
                "nextBytes(array) must link to kk_random_nextBytes")
    }

    /// nextBytes(size: Int) returning a new ByteArray is registered and linked correctly.
    @Test func testNextBytesSizeOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        // The registered overload takes one ByteArray parameter; the size: Int overload
        // would also have arity 1 but with Int parameter type.
        let intParamOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType
        }
        #expect(intParamOverload != nil, "nextBytes(size: Int): ByteArray overload must be registered")
        if let intParamOverload,
           let signature = sema.symbols.functionSignature(for: intParamOverload)
        {
            #expect(sema.symbols.externalLinkName(for: intParamOverload) == "kk_random_nextBytes_size")
            #expect(signature.canThrow, "nextBytes(size) must expose its negative-size throw path")
        }
    }

    /// nextUBytes(size/array/range) overloads are registered and linked correctly.
    @Test func testNextUBytesOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextUBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        func isUByteArray(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else { return false }
            return interner.resolve(symbol.name) == "UByteArray"
        }

        let sizeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.intType] && isUByteArray(sig.returnType)
        }
        let arrayOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                isUByteArray(sig.parameterTypes[0]) &&
                isUByteArray(sig.returnType)
        }
        let rangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 3 &&
                isUByteArray(sig.parameterTypes[0]) &&
                sig.parameterTypes[1] == sema.types.intType &&
                sig.parameterTypes[2] == sema.types.intType &&
                isUByteArray(sig.returnType)
        }

        #expect(sizeOverload != nil, "nextUBytes(size: Int) must be registered")
        #expect(arrayOverload != nil, "nextUBytes(array: UByteArray) must be registered")
        #expect(rangeOverload != nil, "nextUBytes(array, fromIndex, toIndex) must be registered")
        if let sizeOverload,
           let signature = sema.symbols.functionSignature(for: sizeOverload)
        {
            #expect(sema.symbols.externalLinkName(for: sizeOverload) == "kk_random_nextUBytes_size")
            #expect(signature.canThrow, "nextUBytes(size) must expose negative-size failures")
        }
        if let arrayOverload,
           let signature = sema.symbols.functionSignature(for: arrayOverload)
        {
            #expect(sema.symbols.externalLinkName(for: arrayOverload) == "kk_random_nextUBytes")
            #expect(!(signature.canThrow))
        }
        if let rangeOverload,
           let signature = sema.symbols.functionSignature(for: rangeOverload)
        {
            #expect(sema.symbols.externalLinkName(for: rangeOverload) == "kk_random_nextUBytes_range")
            #expect(signature.canThrow, "nextUBytes(array, fromIndex, toIndex) must expose bounds failures")
        }
    }

    // MARK: - nextBits member

    /// nextBits(bitCount: Int) is registered and linked to kk_random_nextBits.
    @Test func testNextBitsMemberIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBits"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let nextBits = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.intType] &&
                sig.returnType == sema.types.intType
        }
        #expect(nextBits != nil, "nextBits(bitCount: Int) member must be registered")
        if let nextBits,
           let signature = sema.symbols.functionSignature(for: nextBits)
        {
            #expect(sema.symbols.externalLinkName(for: nextBits) == "kk_random_nextBits")
            #expect(signature.canThrow, "nextBits(bitCount) must expose its bitCount bounds checks")
        }
    }

    /// nextBytes(array, fromIndex, toIndex) is registered and linked correctly.
    @Test func testNextBytesArrayRangeOverloadIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let rangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 3 &&
                sig.parameterTypes.dropFirst().allSatisfy { $0 == sema.types.intType }
        }
        #expect(rangeOverload != nil, "nextBytes(array, fromIndex, toIndex) overload must be registered")
        if let rangeOverload,
           let signature = sema.symbols.functionSignature(for: rangeOverload)
        {
            #expect(sema.symbols.externalLinkName(for: rangeOverload) == "kk_random_nextBytes_range")
            #expect(signature.canThrow, "nextBytes(array, fromIndex, toIndex) must expose its bounds checks")
        }
    }

    // MARK: - nextInt(IntRange) extension

    /// nextInt(range: IntRange) extension-style overload is registered on Random.
    @Test func testNextIntIntRangeExtensionIsRegistered() throws {
        let (sema, interner) = try makeSema()

        // The extension fun Random.nextInt(range: IntRange) would be in the
        // kotlin.random package as a top-level function or as an additional
        // nextInt overload with an IntRange receiver parameter.
        let fq = ["kotlin", "random", "Random", "nextInt"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        // IntRange would appear as a class type parameter; check by looking for
        // an arity-1 overload whose parameter type is a class (not Int primitive).
        let intRangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id),
                  sig.parameterTypes.count == 1,
                  let paramType = sig.parameterTypes.first
            else { return false }
            // Int primitive type has kind .primitive; IntRange would be .classType
            if case .primitive = sema.types.kind(of: paramType) { return false }
            return true
        }
        #expect(intRangeOverload != nil, "nextInt(range: IntRange) overload must be registered")
        if let intRangeOverload,
           let signature = sema.symbols.functionSignature(for: intRangeOverload)
        {
            #expect(sema.symbols.externalLinkName(for: intRangeOverload) == "kk_random_nextInt_rangeObject")
            #expect(signature.returnType == sema.types.intType)
            #expect(signature.canThrow, "nextInt(range) must expose the empty-range throw path")
        }
    }

    // MARK: - range.random(random: Random)

    @Test func testRangeRandomOverloadsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookup(fqName: randomFQ))
        let randomType = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let cases: [(typeName: String, expectedLink: String)] = [
            ("CharRange", "kk_char_range_random_random"),
            ("IntRange", "kk_range_random_random"),
            ("LongRange", "kk_long_range_random_random"),
            ("UIntRange", "kk_uint_range_random_random"),
            ("ULongRange", "kk_ulong_range_random_random"),
        ]

        for (typeName, expectedLink) in cases {
            let fq = ["kotlin", "ranges", typeName, "random"].map { interner.intern($0) }
            let candidates = sema.symbols.lookupAll(fqName: fq)
            let overload = candidates.first { id in
                guard let sig = sema.symbols.functionSignature(for: id) else { return false }
                return sig.parameterTypes.count == 1 && sig.parameterTypes.first == randomType
            }
            #expect(overload != nil, "\(typeName).random(random: Random) must be registered")
            if let overload {
                #expect(sema.symbols.externalLinkName(for: overload) == expectedLink)
            }
        }
    }
}
#endif
