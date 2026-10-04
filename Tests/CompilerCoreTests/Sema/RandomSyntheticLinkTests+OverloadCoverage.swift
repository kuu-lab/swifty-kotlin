#if canImport(Testing)
/// Sema overload-resolution coverage for kotlin.random.Random
/// Task: STDLIB-RANDOM-001 (API list) + STDLIB-RANDOM-002 (sema/lowering)
///
/// Each test verifies a specific overload-selection or stub-presence property.
/// Tests marked "// GAP:" document capabilities that are not yet registered
/// in the synthetic stub table and will fail until implemented.

@testable import CompilerCore
import Foundation
import Testing

extension RandomSyntheticLinkTests {

    // MARK: - Random factory / implementation structure
    // KSP-685: Random(seed) is the upstream top-level factory function, and the
    // concrete XorWowRandom implementation is internal to kotlin.random.

    /// Random(seed: Int) top-level factory is registered with a Random return type.
    @Test
    func testRandomIntSeedFactoryIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookupAll(fqName: randomFQ).first {
            sema.symbols.symbol($0)?.kind == .class
        })
        let randomType = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let intSeedFactory = sema.symbols.lookupAll(fqName: randomFQ).first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType &&
                sig.returnType == randomType
        }
        #expect(intSeedFactory != nil, "Random(seed: Int) top-level factory must exist")

        if let intSeedFactory {
            #expect(sema.symbols.externalLinkName(for: intSeedFactory) == nil,
                    "Random(seed: Int) must be a real Kotlin function, not a native bridge")
        }
    }

    /// Random(seed: Long) top-level factory is registered with a Random return type.
    @Test
    func testRandomLongSeedFactoryIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookupAll(fqName: randomFQ).first {
            sema.symbols.symbol($0)?.kind == .class
        })
        let randomType = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let longSeedFactory = sema.symbols.lookupAll(fqName: randomFQ).first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.longType &&
                sig.returnType == randomType
        }
        #expect(longSeedFactory != nil, "Random(seed: Long) top-level factory must exist")

        if let longSeedFactory {
            #expect(sema.symbols.externalLinkName(for: longSeedFactory) == nil,
                    "Random(seed: Long) must be a real Kotlin function, not a native bridge")
        }
    }

    @Test
    func testRandomIsAbstractAndXorWowRandomIsInternal() throws {
        let (sema, interner) = try sharedSema()

        #expect(!sema.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-FINAL" }),
                "Random source must not report an invalid XorWowRandom override")

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookupAll(fqName: randomFQ).first {
            sema.symbols.symbol($0)?.kind == .class
        })
        let randomInfo = try #require(sema.symbols.symbol(randomSymbol))
        #expect(randomInfo.kind == .class)
        #expect(randomInfo.flags.contains(.abstractType), "Random must be abstract")

        let nextIntFQ = randomFQ + [interner.intern("nextInt")]
        let nextInt = try #require(sema.symbols.lookupAll(fqName: nextIntFQ).first {
            sema.symbols.functionSignature(for: $0)?.parameterTypes.isEmpty == true
        })
        #expect(sema.symbols.symbol(nextInt)?.flags.contains(.openType) == true,
                "Random.nextInt() must remain open for XorWowRandom")

        let xorWowFQ = ["kotlin", "random", "XorWowRandom"].map { interner.intern($0) }
        let xorWowSymbol = try #require(sema.symbols.lookup(fqName: xorWowFQ))
        let xorWowInfo = try #require(sema.symbols.symbol(xorWowSymbol))
        #expect(xorWowInfo.kind == .class)
        #expect(xorWowInfo.visibility == .internal, "XorWowRandom must remain internal")
        #expect(sema.symbols.directSupertypes(for: xorWowSymbol).contains(randomSymbol))
    }

    // MARK: - Random.Default singleton

    /// Random.Default is registered as a real named companion object (KSP-466:
    /// no longer a synthetic property bridged to the deleted kk_random_default).
    @Test
    func testRandomDefaultSingletonIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSym = try #require(sema.symbols.lookup(fqName: randomFQ))

        let companionSym = sema.symbols.companionObjectSymbol(for: randomSym)
        #expect(companionSym != nil, "Random.Default companion object must be registered")

        if let companionSym {
            #expect(interner.resolve(sema.symbols.symbol(companionSym)!.name) == "Default")
            #expect(sema.symbols.externalLinkName(for: companionSym) == nil, "Random.Default is real Kotlin, not a native bridge")
        }
    }

    // MARK: - nextInt / nextLong overload selection
    // MIGRATION-RANDOM-001: nextInt / nextLong / nextFloat / nextDouble / nextBoolean / nextBytes(array)
    // are migrated to Kotlin source as extension functions (FQ: kotlin.random.nextInt etc.).
    // Tests checking for these as synthetic stubs at kotlin.random.Random.nextInt (with external
    // link names like kk_random_nextInt_until) have been removed.

    // KSP-466: nextULong() / nextULong(until) / nextULong(from, until) are now real
    // Kotlin class members (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt), with
    // only the range-object engines retained as private __kk_* bridges (KSP-457).
    @Test
    func testNextULongOverloadsAreRegistered() throws {
        let (sema, interner) = try sharedSema()

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
        #expect(sema.symbols.externalLinkName(for: zero) == nil)

        // canThrow is a native-bridge ABI calling-convention detail (an extra
        // outThrown pointer parameter); real Kotlin source functions like these
        // don't set it even though they do throw (via require(...) internally).
        let until = try #require(candidate(parameterTypes: [sema.types.ulongType]))
        #expect(sema.symbols.externalLinkName(for: until) == nil)
        #expect(sema.symbols.functionSignature(for: until)?.returnType == sema.types.ulongType)

        let range = try #require(candidate(parameterTypes: [sema.types.ulongType, sema.types.ulongType]))
        #expect(sema.symbols.externalLinkName(for: range) == nil)
        #expect(sema.symbols.functionSignature(for: range)?.returnType == sema.types.ulongType)

        let ulongRange = try #require(candidate(parameterTypes: [ulongRangeType]))
        #expect(sema.symbols.externalLinkName(for: ulongRange) == nil)
        #expect(sema.symbols.functionSignature(for: ulongRange)?.returnType == sema.types.ulongType)
    }

    // MARK: - nextUInt overload selection

    /// nextUInt() / nextUInt(until) / nextUInt(from, until) / nextUInt(range) are registered.
    @Test
    func testNextUIntOverloadsAreRegistered() throws {
        let (sema, interner) = try sharedSema()

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
        // KSP-466: the scalar overloads are now real Kotlin class members
        // (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt); only the
        // UIntRange-typed overload is now a real Kotlin member whose body calls
        // the private __kk_* engine bridge.
        if let zero {
            #expect(sema.symbols.externalLinkName(for: zero) == nil)
        }
        // Source-backed members have no synthetic external link or bridge-level
        // thrown-channel metadata.
        if let until {
            #expect(sema.symbols.externalLinkName(for: until) == nil)
        }
        if let fromUntil {
            #expect(sema.symbols.externalLinkName(for: fromUntil) == nil)
        }
        if let range,
           let signature = sema.symbols.functionSignature(for: range)
        {
            #expect(sema.symbols.externalLinkName(for: range) == nil)
            #expect(!signature.canThrow)
        }
    }

    // MARK: - nextBytes overloads
    // KSP-466: nextBytes(array/size/array+range) are real Kotlin class members on
    // kotlin.random.Random (Random.kt), matching upstream's own class layout,
    // not package-level extensions and not synthetic stubs. externalLinkName is
    // nil for all of them (no native bridge remains).

    private func byteArrayType(sema: SemaModule, interner: StringInterner) throws -> TypeID {
        let fqName = ["kotlin", "ByteArray"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
    }

    /// nextBytes(size: Int) returning a new ByteArray is registered as a real member.
    @Test
    func testNextBytesSizeOverloadIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let byteArray = try byteArrayType(sema: sema, interner: interner)

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let intParamOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.intType] && sig.returnType == byteArray
        }
        #expect(intParamOverload != nil, "nextBytes(size: Int): ByteArray overload must be registered")
        if let intParamOverload {
            #expect(sema.symbols.externalLinkName(for: intParamOverload) == nil)
        }
    }

    /// nextUBytes(size/array/range) overloads are registered as package-level
    /// extensions on Random (matching upstream URandom.kt), linked correctly.
    @Test
    func testNextUBytesOverloadsAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "nextUBytes"].map { interner.intern($0) }
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
        if let sizeOverload {
            #expect(sema.symbols.externalLinkName(for: sizeOverload) == nil)
        }
        if let arrayOverload {
            #expect(sema.symbols.externalLinkName(for: arrayOverload) == nil)
        }
        if let rangeOverload {
            #expect(sema.symbols.externalLinkName(for: rangeOverload) == nil)
        }
    }

    // MARK: - nextBits member

    /// nextBits(bitCount: Int) is registered as a real Kotlin member (KSP-466:
    /// no longer bridged to the deleted kk_random_nextBits).
    @Test
    func testNextBitsMemberIsRegistered() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "Random", "nextBits"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let nextBits = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes == [sema.types.intType] &&
                sig.returnType == sema.types.intType
        }
        #expect(nextBits != nil, "nextBits(bitCount: Int) member must be registered")
        if let nextBits {
            #expect(sema.symbols.externalLinkName(for: nextBits) == nil)
        }
    }

    /// nextBytes(array, fromIndex, toIndex) is registered and linked correctly.
    @Test
    func testNextBytesArrayRangeOverloadIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let byteArray = try byteArrayType(sema: sema, interner: interner)

        let fq = ["kotlin", "random", "Random", "nextBytes"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let rangeOverload = candidates.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 3 &&
                sig.parameterTypes[0] == byteArray &&
                sig.parameterTypes[1] == sema.types.intType &&
                sig.parameterTypes[2] == sema.types.intType
        }
        #expect(rangeOverload != nil, "nextBytes(array, fromIndex, toIndex) overload must be registered")
        if let rangeOverload {
            #expect(sema.symbols.externalLinkName(for: rangeOverload) == nil)
        }
    }

    // MARK: - nextInt(IntRange) — source-backed member

    // MARK: - range.random(random: Random)

    @Test
    func testRangeRandomOverloadsAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()

        for typeName in ["CharRange", "IntRange", "LongRange", "UIntRange", "ULongRange"] {
            for member in ["random", "randomOrNull"] {
                let fq = ["kotlin", "ranges", typeName, member].map { interner.intern($0) }
                for symbol in sema.symbols.lookupAll(fqName: fq) {
                    #expect(
                        sema.symbols.externalLinkName(for: symbol) == nil,
                        "\(typeName).\(member) must be source-backed"
                    )
                }
            }
        }
    }
}
#endif
