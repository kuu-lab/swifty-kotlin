#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CoercionSyntheticStubTests {

    private func coercionSymbols(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let fq = ["kotlin", "ranges", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq)
    }

    private func nominalRangeType(
        named name: String,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> TypeID {
        let fqName = ["kotlin", "ranges", name].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "Expected synthetic range type \(name)"
        )
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func assertCoercionStub(
        member: String,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        expectedLink: String,
        sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let symbols = coercionSymbols(for: member, sema: sema, interner: interner)
        let matchingSymbol = symbols.first { symbolID in
            guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == receiverType
                && sig.parameterTypes == parameterTypes
                && sig.returnType == returnType
        }
        let sym = try #require(matchingSymbol, "Expected \(expectedLink) coercion stub")
        #expect(
            sema.symbols.externalLinkName(for: sym) == expectedLink,
            "\(expectedLink) should be registered for \(member)"
        )
    }

    @Test
    func testCoercionSyntheticStubTestsSurfaceInventory() throws {
        let source = """
        fun noop() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = ctx
            // Byte and Short are normalized to Int in the compiler, so they reuse the
            // Int coercion stubs rather than registering separate symbols.
            // MARK: - Int coercion stubs

            // === testIntCoercionStubsHaveCorrectExternalLinks ===
            do {

                // MIGRATION-RANGE-003: coerceIn(min,max)/coerceAtLeast/coerceAtMost migrated to
                // bundled Kotlin source (RangeCoercion.kt). Only coerceIn(range:) remains as a
                // synthetic stub, so we only verify the range overload's external link here.
                let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
                    ("coerceIn", [sema.types.intType], "kk_int_coerceIn"),
                ]

                for entry in expected {
                    let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
                    let matchingSymbol = symbols.first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.receiverType == sema.types.intType
                            && sig.parameterTypes == entry.paramTypes
                            && sig.returnType == sema.types.intType
                    }
                    let sym = try #require(matchingSymbol, "Expected Int.\(entry.member) coercion stub")
                    #expect(
                        sema.symbols.externalLinkName(for: sym) == entry.link,
                        "Int.\(entry.member) should link to \(entry.link)"
                    )
                }
            }

            // === testIntCoerceInSignatureHasTwoIntParameters ===
            do {

                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.intType
                        && sig.parameterTypes == [sema.types.intType, sema.types.intType]
                }
                let sym = try #require(matchingSymbol, "Expected Int.coerceIn stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.intType)
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
            }

            // === testIntCoerceAtLeastSignatureHasOneIntParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.intType
                        && sig.parameterTypes == [sema.types.intType]
                }
                let sym = try #require(matchingSymbol, "Expected Int.coerceAtLeast stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.intType)
                #expect(sig.parameterTypes == [sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
            }

            // === testIntCoerceAtMostSignatureHasOneIntParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.intType
                        && sig.parameterTypes == [sema.types.intType]
                }
                let sym = try #require(matchingSymbol, "Expected Int.coerceAtMost stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.intType)
                #expect(sig.parameterTypes == [sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
            }
            // MARK: - Long coercion stubs

            // === testLongCoercionStubsHaveCorrectExternalLinks ===
            do {

                // MIGRATION-RANGE-003: coerceIn(min,max)/coerceAtLeast/coerceAtMost migrated to
                // bundled Kotlin source (RangeCoercion.kt). Only coerceIn(range:) remains as a
                // synthetic stub, so we only verify the range overload's external link here.
                let expected: [(member: String, paramTypes: [TypeID], link: String)] = [
                    ("coerceIn", [sema.types.longType], "kk_long_coerceIn"),
                ]

                for entry in expected {
                    let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
                    let matchingSymbol = symbols.first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.receiverType == sema.types.longType
                            && sig.parameterTypes == entry.paramTypes
                            && sig.returnType == sema.types.longType
                    }
                    let sym = try #require(matchingSymbol, "Expected Long.\(entry.member) coercion stub")
                    #expect(
                        sema.symbols.externalLinkName(for: sym) == entry.link,
                        "Long.\(entry.member) should link to \(entry.link)"
                    )
                }
            }

            // === testLongCoerceInSignatureHasTwoLongParameters ===
            do {

                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.longType
                        && sig.parameterTypes == [sema.types.longType, sema.types.longType]
                }
                let sym = try #require(matchingSymbol, "Expected Long.coerceIn stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.longType)
                #expect(sig.parameterTypes == [sema.types.longType, sema.types.longType])
                #expect(sig.returnType == sema.types.longType)
            }

            // === testLongCoerceAtLeastSignatureHasOneLongParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.longType
                        && sig.parameterTypes == [sema.types.longType]
                }
                let sym = try #require(matchingSymbol, "Expected Long.coerceAtLeast stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.longType)
                #expect(sig.parameterTypes == [sema.types.longType])
                #expect(sig.returnType == sema.types.longType)
            }

            // === testLongCoerceAtMostSignatureHasOneLongParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.longType
                        && sig.parameterTypes == [sema.types.longType]
                }
                let sym = try #require(matchingSymbol, "Expected Long.coerceAtMost stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.longType)
                #expect(sig.parameterTypes == [sema.types.longType])
                #expect(sig.returnType == sema.types.longType)
            }
            // MARK: - Double coercion stubs

            // === testDoubleCoercionStubsHaveCorrectExternalLinks ===
            do {

                // MIGRATION-RANGE-003: Double.coerceIn/coerceAtLeast/coerceAtMost migrated to
                // bundled Kotlin source (RangeCoercion.kt). No synthetic stubs remain for these
                // overloads, so this test now verifies that no stale stubs are registered.

                let migrated: [(member: String, paramTypes: [TypeID])] = [
                    ("coerceIn", [sema.types.doubleType, sema.types.doubleType]),
                    ("coerceAtLeast", [sema.types.doubleType]),
                    ("coerceAtMost", [sema.types.doubleType]),
                ]

                for entry in migrated {
                    let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
                    let matchingStub = symbols.first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.receiverType == sema.types.doubleType
                            && sig.parameterTypes == entry.paramTypes
                            && sig.returnType == sema.types.doubleType
                            && sema.symbols.externalLinkName(for: symbolID) != nil
                    }
                    #expect(matchingStub == nil, "Double.\(entry.member) should not have a synthetic stub with external link")
                }
            }

            // === testDoubleCoerceInSignatureHasTwoDoubleParameters ===
            do {

                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.doubleType
                        && sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType]
                }
                let sym = try #require(matchingSymbol, "Expected Double.coerceIn stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.doubleType)
                #expect(sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType])
                #expect(sig.returnType == sema.types.doubleType)
            }

            // === testDoubleCoerceAtLeastSignatureHasOneDoubleParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.doubleType
                        && sig.parameterTypes == [sema.types.doubleType]
                }
                let sym = try #require(matchingSymbol, "Expected Double.coerceAtLeast stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.doubleType)
                #expect(sig.parameterTypes == [sema.types.doubleType])
                #expect(sig.returnType == sema.types.doubleType)
            }

            // === testDoubleCoerceAtMostSignatureHasOneDoubleParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.doubleType
                        && sig.parameterTypes == [sema.types.doubleType]
                }
                let sym = try #require(matchingSymbol, "Expected Double.coerceAtMost stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.doubleType)
                #expect(sig.parameterTypes == [sema.types.doubleType])
                #expect(sig.returnType == sema.types.doubleType)
            }
            // MARK: - Float coercion stubs

            // === testFloatCoercionStubsHaveCorrectExternalLinks ===
            do {

                // MIGRATION-RANGE-003: Float.coerceIn/coerceAtLeast/coerceAtMost migrated to
                // bundled Kotlin source (RangeCoercion.kt). No synthetic stubs remain for these
                // overloads, so this test now verifies that no stale stubs are registered.

                let migrated: [(member: String, paramTypes: [TypeID])] = [
                    ("coerceIn", [sema.types.floatType, sema.types.floatType]),
                    ("coerceAtLeast", [sema.types.floatType]),
                    ("coerceAtMost", [sema.types.floatType]),
                ]

                for entry in migrated {
                    let symbols = coercionSymbols(for: entry.member, sema: sema, interner: interner)
                    let matchingStub = symbols.first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.receiverType == sema.types.floatType
                            && sig.parameterTypes == entry.paramTypes
                            && sig.returnType == sema.types.floatType
                            && sema.symbols.externalLinkName(for: symbolID) != nil
                    }
                    #expect(matchingStub == nil, "Float.\(entry.member) should not have a synthetic stub with external link")
                }
            }

            // === testFloatCoerceInSignatureHasTwoFloatParameters ===
            do {

                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.floatType
                        && sig.parameterTypes == [sema.types.floatType, sema.types.floatType]
                }
                let sym = try #require(matchingSymbol, "Expected Float.coerceIn stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.floatType)
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType])
                #expect(sig.returnType == sema.types.floatType)
            }

            // === testFloatCoerceAtLeastSignatureHasOneFloatParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.floatType
                        && sig.parameterTypes == [sema.types.floatType]
                }
                let sym = try #require(matchingSymbol, "Expected Float.coerceAtLeast stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.floatType)
                #expect(sig.parameterTypes == [sema.types.floatType])
                #expect(sig.returnType == sema.types.floatType)
            }

            // === testFloatCoerceAtMostSignatureHasOneFloatParameter ===
            do {

                let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
                let matchingSymbol = symbols.first { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == sema.types.floatType
                        && sig.parameterTypes == [sema.types.floatType]
                }
                let sym = try #require(matchingSymbol, "Expected Float.coerceAtMost stub")
                let sig = try #require(sema.symbols.functionSignature(for: sym))

                #expect(sig.receiverType == sema.types.floatType)
                #expect(sig.parameterTypes == [sema.types.floatType])
                #expect(sig.returnType == sema.types.floatType)
            }
            // MARK: - Unsigned coercion stubs

            // === testUnsignedCoercionStubsHaveCorrectExternalLinks ===
            do {

                let expected: [(member: String, receiverType: TypeID, parameterTypes: [TypeID], link: String)] = [
                    ("coerceIn", sema.types.ubyteType, [sema.types.ubyteType, sema.types.ubyteType], "kk_ubyte_coerceIn"),
                    ("coerceAtLeast", sema.types.ubyteType, [sema.types.ubyteType], "kk_ubyte_coerceAtLeast"),
                    ("coerceAtMost", sema.types.ubyteType, [sema.types.ubyteType], "kk_ubyte_coerceAtMost"),
                    ("coerceIn", sema.types.ushortType, [sema.types.ushortType, sema.types.ushortType], "kk_ushort_coerceIn"),
                    ("coerceAtLeast", sema.types.ushortType, [sema.types.ushortType], "kk_ushort_coerceAtLeast"),
                    ("coerceAtMost", sema.types.ushortType, [sema.types.ushortType], "kk_ushort_coerceAtMost"),
                    ("coerceIn", sema.types.uintType, [sema.types.uintType, sema.types.uintType], "kk_uint_coerceIn"),
                    ("coerceAtLeast", sema.types.uintType, [sema.types.uintType], "kk_uint_coerceAtLeast"),
                    ("coerceAtMost", sema.types.uintType, [sema.types.uintType], "kk_uint_coerceAtMost"),
                    ("coerceIn", sema.types.ulongType, [sema.types.ulongType, sema.types.ulongType], "kk_ulong_coerceIn"),
                    ("coerceAtLeast", sema.types.ulongType, [sema.types.ulongType], "kk_ulong_coerceAtLeast"),
                    ("coerceAtMost", sema.types.ulongType, [sema.types.ulongType], "kk_ulong_coerceAtMost"),
                ]

                for entry in expected {
                    try assertCoercionStub(
                        member: entry.member,
                        receiverType: entry.receiverType,
                        parameterTypes: entry.parameterTypes,
                        returnType: entry.receiverType,
                        expectedLink: entry.link,
                        sema: sema,
                        interner: interner
                    )
                }
            }

            // === testUnsignedRangeCoerceInDoesNotRegisterSyntheticStubs ===
            do {

                let uintRangeType = try nominalRangeType(named: "UIntRange", sema: sema, interner: interner)
                let ulongRangeType = try nominalRangeType(named: "ULongRange", sema: sema, interner: interner)
                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)

                let hasRangeStub = symbols.contains { symbolID in
                    guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                    return (sig.receiverType == sema.types.uintType && sig.parameterTypes == [uintRangeType])
                        || (sig.receiverType == sema.types.ulongType && sig.parameterTypes == [ulongRangeType])
                }

                #expect(
                    !hasRangeStub,
                    "UInt/ULong coerceIn(range) should be handled by the type-checker range fast path, not synthetic stubs"
                )
            }
            // MARK: - Cross-type: all numeric types register distinct overloads

            // === testAllNumericTypesRegisterDistinctCoerceInOverloads ===
            do {

                let symbols = coercionSymbols(for: "coerceIn", sema: sema, interner: interner)
                let expectedReceiverTypes: Set<TypeID> = [
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.doubleType,
                    sema.types.floatType,
                    sema.types.ubyteType,
                    sema.types.ushortType,
                    sema.types.uintType,
                    sema.types.ulongType,
                ]

                var foundReceiverTypes: Set<TypeID> = []
                for symbolID in symbols {
                    if let sig = sema.symbols.functionSignature(for: symbolID),
                       let receiver = sig.receiverType,
                       expectedReceiverTypes.contains(receiver) {
                        foundReceiverTypes.insert(receiver)
                    }
                }

                #expect(
                    foundReceiverTypes == expectedReceiverTypes,
                    "coerceIn should have stubs for Int, Long, Double, Float, UByte, UShort, UInt, and ULong"
                )
            }

            // === testAllNumericTypesRegisterDistinctCoerceAtLeastOverloads ===
            do {

                let symbols = coercionSymbols(for: "coerceAtLeast", sema: sema, interner: interner)
                let expectedReceiverTypes: Set<TypeID> = [
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.doubleType,
                    sema.types.floatType,
                    sema.types.ubyteType,
                    sema.types.ushortType,
                    sema.types.uintType,
                    sema.types.ulongType,
                ]

                var foundReceiverTypes: Set<TypeID> = []
                for symbolID in symbols {
                    if let sig = sema.symbols.functionSignature(for: symbolID),
                       let receiver = sig.receiverType,
                       expectedReceiverTypes.contains(receiver) {
                        foundReceiverTypes.insert(receiver)
                    }
                }

                #expect(
                    foundReceiverTypes == expectedReceiverTypes,
                    "coerceAtLeast should have stubs for Int, Long, Double, Float, UByte, UShort, UInt, and ULong"
                )
            }

            // === testAllNumericTypesRegisterDistinctCoerceAtMostOverloads ===
            do {

                let symbols = coercionSymbols(for: "coerceAtMost", sema: sema, interner: interner)
                let expectedReceiverTypes: Set<TypeID> = [
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.doubleType,
                    sema.types.floatType,
                    sema.types.ubyteType,
                    sema.types.ushortType,
                    sema.types.uintType,
                    sema.types.ulongType,
                ]

                var foundReceiverTypes: Set<TypeID> = []
                for symbolID in symbols {
                    if let sig = sema.symbols.functionSignature(for: symbolID),
                       let receiver = sig.receiverType,
                       expectedReceiverTypes.contains(receiver) {
                        foundReceiverTypes.insert(receiver)
                    }
                }

                #expect(
                    foundReceiverTypes == expectedReceiverTypes,
                    "coerceAtMost should have stubs for Int, Long, Double, Float, UByte, UShort, UInt, and ULong"
                )
            }
            // MARK: - Package parenting

            // === testKotlinRangesPackageIsParentedUnderKotlinPackage ===
            do {

                _ = try #require(
                    sema.symbols.lookup(fqName: [interner.intern("kotlin")])
                )
                _ = try #require(
                    sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("ranges")])
                )
            }
        }
    }

}
#endif
