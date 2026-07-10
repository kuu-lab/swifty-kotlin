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

    // MARK: - Random factory / seed constructors
    // KSP-466: Random(seed: Int) / Random(seed: Long) are now real Kotlin secondary
    // constructors (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt) parsed like
    // any other bundled source, not synthetic stubs bridged to the deleted
    // kk_random_create_seeded. externalLinkName is nil for a real constructor body.

    /// Random(seed: Int) secondary constructor is registered.
    @Test
    func testRandomIntSeedConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let ctorFQ = ["kotlin", "random", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: ctorFQ)
        #expect(!(ctors.isEmpty), "Random <init> constructor must be registered")

        let intSeedCtor = ctors.first { id in
            guard let sig = sema.symbols.functionSignature(for: id) else { return false }
            return sig.parameterTypes.count == 1 &&
                sig.parameterTypes.first == sema.types.intType
        }
        #expect(intSeedCtor != nil, "Random(seed: Int) constructor must exist")

        if let ctor = intSeedCtor {
            #expect(sema.symbols.externalLinkName(for: ctor) == nil, "Random(seed: Int) is real Kotlin, not a native bridge")
        }
    }

    /// Random(seed: Long) secondary constructor is registered.
    @Test
    func testRandomLongSeedConstructorIsRegistered() throws {
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
            #expect(sema.symbols.externalLinkName(for: ctor) == nil, "Random(seed: Long) is real Kotlin, not a native bridge")
        }
    }

    // MARK: - Random.Default singleton

    /// Random.Default is registered as a real named companion object (KSP-466:
    /// no longer a synthetic property bridged to the deleted kk_random_default).
    @Test
    func testRandomDefaultSingletonIsRegistered() throws {
        let (sema, interner) = try makeSema()

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
    // Kotlin class members (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt), not
    // synthetic stubs bridged to kk_random_nextULong/_until/_range (all deleted). Only
    // the UIntRange/ULongRange-typed overload stays native (KSP-457 scope).
    @Test
    func testNextULongOverloadsAreRegistered() throws {
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
        #expect(sema.symbols.externalLinkName(for: ulongRange) == "kk_random_nextULong_ulongRange")
        #expect(sema.symbols.functionSignature(for: ulongRange)?.returnType == sema.types.ulongType)
        #expect(sema.symbols.functionSignature(for: ulongRange)?.canThrow ?? false)
    }

    // MARK: - nextUInt overload selection

    /// nextUInt() / nextUInt(until) / nextUInt(from, until) / nextUInt(range) are registered.
    @Test
    func testNextUIntOverloadsAreRegistered() throws {
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
        // KSP-466: the scalar overloads are now real Kotlin class members
        // (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt); only the
        // UIntRange-typed overload stays a native bridge (KSP-457 scope).
        if let zero {
            #expect(sema.symbols.externalLinkName(for: zero) == nil)
        }
        // canThrow is a native-bridge ABI calling-convention detail; the real
        // Kotlin `until`/`fromUntil` members don't set it despite throwing via
        // require(...) internally. Only the kept native uintRange bridge does.
        if let until {
            #expect(sema.symbols.externalLinkName(for: until) == nil)
        }
        if let fromUntil {
            #expect(sema.symbols.externalLinkName(for: fromUntil) == nil)
        }
        if let range,
           let signature = sema.symbols.functionSignature(for: range)
        {
            #expect(sema.symbols.externalLinkName(for: range) == "kk_random_nextUInt_uintRange")
            #expect(signature.canThrow)
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
        let (sema, interner) = try makeSema()
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
        let (sema, interner) = try makeSema()

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
        let (sema, interner) = try makeSema()

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
        let (sema, interner) = try makeSema()
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

    // MARK: - nextInt(IntRange) — package-level extension stub

    // MARK: - range.random(random: Random)

    @Test
    func testRangeRandomOverloadsAreRegistered() throws {
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
