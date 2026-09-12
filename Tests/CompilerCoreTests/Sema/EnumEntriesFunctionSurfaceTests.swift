#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct EnumEntriesFunctionSurfaceTests {
    private static let fixture = SemaFixture(surface: "enumEntries")

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        try Self.fixture.shared()
    }

    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        try Self.fixture.make(source: source)
    }

    @Test func testEnumEntriesFunctionIsRegisteredUnderKotlinEnums() throws {
        let (sema, interner) = try sharedSema()
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        #expect(sema.symbols.symbol(enumEntriesSymbol)?.kind == .function)
        #expect(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enumEntries"),
        ]) == nil)
    }

    @Test func testEnumEntriesFunctionIsDefaultImportedFromKotlinEnums() throws {
        let source = """
        enum class Color { RED, BLUE }
        fun entries() = enumEntries<Color>()
        """
        let (sema, interner) = try makeSema(source: source)
        let enumEntriesSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("enums"),
            interner.intern("enumEntries"),
        ]))
        let entriesFunction = try #require(sema.symbols.lookup(fqName: [
            interner.intern("entries"),
        ]))
        let signature = try #require(sema.symbols.functionSignature(for: entriesFunction))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            Issue.record("enumEntries<Color>() should return an EnumEntries-like class type"); return
        }
        let callBindingsContains = sema.bindings.callBindings.contains(where: { $0.value.chosenCallee == enumEntriesSymbol })
        #expect(
            callBindingsContains,
            "Unqualified enumEntries<Color>() should bind to kotlin.enums.enumEntries"
        )
    }

    @Test func testKSP1156RegistersExactTopLevelOverloadSet() throws {
        let (sema, interner) = try sharedSema()
        let kotlinEnums = [interner.intern("kotlin"), interner.intern("enums")]
        let enumEntriesFQName = kotlinEnums + [interner.intern("enumEntries")]
        let overloads = sema.symbols.lookupAll(fqName: enumEntriesFQName).compactMap { symbolID -> (SemanticSymbol, FunctionSignature)? in
            guard let symbol = sema.symbols.symbol(symbolID),
                  symbol.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbolID)
            else {
                return nil
            }
            return (symbol, signature)
        }
        #expect(overloads.count == 3, "KSP-1156 requires no-arg, Array, and provider enumEntries overloads")

        let noArg = try #require(overloads.first { $0.1.parameterTypes.isEmpty })
        #expect(noArg.0.visibility == .public)
        #expect(noArg.0.flags.contains(.inlineFunction))
        #expect(noArg.1.reifiedTypeParameterIndices == [0])

        let arraySymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")]))
        let arrayOverload = try #require(overloads.first { candidate in
            guard candidate.1.parameterTypes.count == 1,
                  case let .classType(parameterType) = sema.types.kind(of: candidate.1.parameterTypes[0])
            else { return false }
            return parameterType.classSymbol == arraySymbol
        })
        #expect(arrayOverload.0.visibility == .internal)

        let providerOverload = try #require(overloads.first { candidate in
            guard candidate.1.parameterTypes.count == 1,
                  case let .functionType(functionType) = sema.types.kind(of: candidate.1.parameterTypes[0])
            else { return false }
            guard functionType.params.isEmpty else { return false }
            if case .classType = sema.types.kind(of: functionType.returnType) {
                return true
            }
            return false
        })
        #expect(providerOverload.0.visibility == .internal)

        let intrinsic = try #require(sema.symbols.lookup(fqName: kotlinEnums + [interner.intern("enumEntriesIntrinsic")]))
        let intrinsicInfo = try #require(sema.symbols.symbol(intrinsic))
        let intrinsicSignature = try #require(sema.symbols.functionSignature(for: intrinsic))
        #expect(intrinsicInfo.kind == .function)
        #expect(intrinsicInfo.visibility == .internal)
        #expect(intrinsicSignature.parameterTypes.isEmpty)
    }
}
#endif
