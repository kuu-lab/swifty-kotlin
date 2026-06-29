#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

private struct _TestHelperFailure: Error {}

@Suite
struct NativeBitSetSurfaceTests {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func bitSetSymbol(
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> SymbolID {
        let fqName = ["kotlin", "native", "BitSet"].map { interner.intern($0) }
        return try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.BitSet must be registered"
        )
    }

    private func classType(
        _ fqPath: [String],
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let fqName = fqPath.map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "\(fqPath.joined(separator: ".")) must be registered"
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func bitSetType(
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let symbol = try bitSetSymbol(in: sema, interner: interner, file: file, line: line)
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func memberSignature(
        named name: String,
        parameters: [TypeID],
        returnType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (SymbolID, FunctionSignature) {
        let ownerSymbol = try bitSetSymbol(in: sema, interner: interner, file: file, line: line)
        let ownerFQName = try #require(sema.symbols.symbol(ownerSymbol)?.fqName)
        let ownerType = try bitSetType(in: sema, interner: interner, file: file, line: line)
        let memberFQName = ownerFQName + [interner.intern(name)]
        let candidates = sema.symbols.lookupAll(fqName: memberFQName)
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.receiverType == ownerType
                && signature.parameterTypes == parameters
                && signature.returnType == returnType
            {
                return (candidate, signature)
            }
        }

        Issue.record("Expected BitSet.\(name)(\(parameters.count) params) -> \(returnType), got \(candidates.compactMap { sema.symbols.functionSignature(for: $0) })")
        throw _TestHelperFailure()
    }

    @Test func testBitSetClassAndCompanionAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let bitSet = try bitSetSymbol(in: sema, interner: interner)
        let companionFQName = ["kotlin", "native", "BitSet", "Companion"].map { interner.intern($0) }
        let companion = try #require(
            sema.symbols.lookup(fqName: companionFQName),
            "kotlin.native.BitSet.Companion must be registered"
        )

        #expect(sema.symbols.symbol(bitSet)?.kind == .class)
        #expect(sema.symbols.symbol(companion)?.kind == .object)
        #expect(sema.symbols.parentSymbol(for: companion) == bitSet)
    }

    @Test func testBitSetCarriesObsoleteNativeApiMarker() throws {
        let (sema, interner) = try makeSema()
        let bitSet = try bitSetSymbol(in: sema, interner: interner)
        let annotations = sema.symbols.annotations(for: bitSet)

        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.native.ObsoleteNativeApi" },
            "BitSet must carry @ObsoleteNativeApi metadata"
        )
    }

    @Test func testBitSetConstructorsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let bitSet = try bitSetSymbol(in: sema, interner: interner)
        let bitSetType = try bitSetType(in: sema, interner: interner)
        let ownerFQName = try #require(sema.symbols.symbol(bitSet)?.fqName)
        let constructors = sema.symbols.lookupAll(fqName: ownerFQName + [interner.intern("<init>")])
        let initializerType = sema.types.make(.functionType(FunctionType(
            params: [sema.types.intType],
            returnType: sema.types.booleanType
        )))

        let sizeConstructor = try #require(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.intType] && signature.returnType == bitSetType
        })
        let sizeSignature = try #require(sema.symbols.functionSignature(for: sizeConstructor))
        #expect(sizeSignature.valueParameterHasDefaultValues == [true])

        let initializerConstructor = try #require(constructors.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return signature.parameterTypes == [sema.types.intType, initializerType]
                && signature.returnType == bitSetType
        })
        let initializerSignature = try #require(sema.symbols.functionSignature(for: initializerConstructor))
        #expect(initializerSignature.valueParameterHasDefaultValues == [false, false])
    }

    @Test func testBitSetPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let bitSet = try bitSetSymbol(in: sema, interner: interner)
        let ownerFQName = try #require(sema.symbols.symbol(bitSet)?.fqName)

        let isEmpty = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern("isEmpty")]))
        let lastTrueIndex = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern("lastTrueIndex")]))
        let size = try #require(sema.symbols.lookup(fqName: ownerFQName + [interner.intern("size")]))

        #expect(sema.symbols.propertyType(for: isEmpty) == sema.types.booleanType)
        #expect(sema.symbols.propertyType(for: lastTrueIndex) == sema.types.intType)
        #expect(sema.symbols.propertyType(for: size) == sema.types.intType)
        #expect(
            sema.symbols.symbol(size)?.flags.contains(.mutable) == true,
            "BitSet.size must be mutable"
        )
    }

    @Test func testBitSetMemberGroupsAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let bitSetType = try bitSetType(in: sema, interner: interner)
        let intRangeType = try classType(["kotlin", "ranges", "IntRange"], sema: sema, interner: interner)
        let unit = sema.types.unitType
        let bool = sema.types.booleanType
        let int = sema.types.intType

        for name in ["and", "andNot", "or", "xor"] {
            _ = try memberSignature(named: name, parameters: [bitSetType], returnType: unit, sema: sema, interner: interner)
        }
        _ = try memberSignature(named: "intersects", parameters: [bitSetType], returnType: bool, sema: sema, interner: interner)

        _ = try memberSignature(named: "clear", parameters: [], returnType: unit, sema: sema, interner: interner)
        _ = try memberSignature(named: "clear", parameters: [int], returnType: unit, sema: sema, interner: interner)
        _ = try memberSignature(named: "clear", parameters: [intRangeType], returnType: unit, sema: sema, interner: interner)
        _ = try memberSignature(named: "clear", parameters: [int, int], returnType: unit, sema: sema, interner: interner)

        _ = try memberSignature(named: "flip", parameters: [int], returnType: unit, sema: sema, interner: interner)
        _ = try memberSignature(named: "flip", parameters: [intRangeType], returnType: unit, sema: sema, interner: interner)
        _ = try memberSignature(named: "flip", parameters: [int, int], returnType: unit, sema: sema, interner: interner)

        let (getSymbol, _) = try memberSignature(named: "get", parameters: [int], returnType: bool, sema: sema, interner: interner)
        #expect(sema.symbols.symbol(getSymbol)?.flags.contains(.operatorFunction) == true)

        let (_, setIndexSignature) = try memberSignature(named: "set", parameters: [int, bool], returnType: unit, sema: sema, interner: interner)
        let (_, setRangeSignature) = try memberSignature(named: "set", parameters: [intRangeType, bool], returnType: unit, sema: sema, interner: interner)
        let (_, setBoundsSignature) = try memberSignature(named: "set", parameters: [int, int, bool], returnType: unit, sema: sema, interner: interner)
        #expect(setIndexSignature.valueParameterHasDefaultValues == [false, true])
        #expect(setRangeSignature.valueParameterHasDefaultValues == [false, true])
        #expect(setBoundsSignature.valueParameterHasDefaultValues == [false, false, true])

        let (_, nextClearSignature) = try memberSignature(named: "nextClearBit", parameters: [int], returnType: int, sema: sema, interner: interner)
        let (_, nextSetSignature) = try memberSignature(named: "nextSetBit", parameters: [int], returnType: int, sema: sema, interner: interner)
        #expect(nextClearSignature.valueParameterHasDefaultValues == [true])
        #expect(nextSetSignature.valueParameterHasDefaultValues == [true])

        _ = try memberSignature(named: "previousBit", parameters: [int, bool], returnType: int, sema: sema, interner: interner)
        _ = try memberSignature(named: "previousClearBit", parameters: [int], returnType: int, sema: sema, interner: interner)
        _ = try memberSignature(named: "previousSetBit", parameters: [int], returnType: int, sema: sema, interner: interner)

        let anyNullable = sema.types.makeNullable(sema.types.anyType)
        _ = try memberSignature(named: "equals", parameters: [anyNullable], returnType: bool, sema: sema, interner: interner)
        _ = try memberSignature(named: "hashCode", parameters: [], returnType: int, sema: sema, interner: interner)
        _ = try memberSignature(named: "toString", parameters: [], returnType: sema.types.stringType, sema: sema, interner: interner)
    }

    @Test func testUsingBitSetWithoutOptInProducesErrorDiagnostic() {
        let source = """
        import kotlin.native.BitSet

        fun probe(bits: BitSet): Boolean = bits.isEmpty
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error
        }

        #expect(
            !(optInErrors.isEmpty),
            "Expected BitSet usage to require ObsoleteNativeApi opt-in"
        )
    }

    @Test func testBitSetSurfaceResolvesWithObsoleteNativeApiOptIn() {
        let source = """
        @file:OptIn(kotlin.native.ObsoleteNativeApi::class)
        import kotlin.native.BitSet

        fun probe(other: BitSet): Boolean {
            val bits = BitSet()
            bits.size = 4
            bits.set(0)
            bits.set(1, false)
            bits.set(0..1)
            bits.set(0, 2)
            bits.flip(0)
            bits.flip(0..1)
            bits.flip(0, 2)
            bits.clear()
            bits.clear(0)
            bits.clear(0..1)
            bits.clear(0, 2)
            bits.and(other)
            bits.or(other)
            bits.xor(other)
            bits.andNot(other)
            val current = bits[0]
            val last = bits.lastTrueIndex
            val next = bits.nextSetBit()
            val clear = bits.nextClearBit()
            val prev = bits.previousBit(bits.size, false)
            return current || bits.isEmpty || bits.intersects(other) || last == next || clear == prev
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(
            errors.isEmpty,
            "Expected BitSet surface to type-check with ObsoleteNativeApi opt-in, got \(errors)"
        )
    }
}
#endif
