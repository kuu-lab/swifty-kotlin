#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpectActualExtensionReceiverTests {
    @Test func testSameNameExtensionPropertiesMatchTheirReceivers() throws {
        let ctx = makeContextFromSources([
            """
            package io.ktor.utils.io.charsets
            expect abstract class CharsetEncoder
            expect abstract class CharsetDecoder
            expect class Charset
            expect val CharsetEncoder.charset: Charset
            expect val CharsetDecoder.charset: Charset
            """,
            """
            package io.ktor.utils.io.charsets
            actual abstract class CharsetEncoder
            actual abstract class CharsetDecoder
            actual class Charset
            actual val CharsetEncoder.charset: Charset get() = TODO()
            actual val CharsetDecoder.charset: Charset get() = TODO()
            """,
        ])
        try runSema(ctx)

        let errors = errorCodes(in: ctx)
        #expect(!errors.contains("KSWIFTK-MPP-AMBIGUOUS"), "Unexpected ambiguity: \(ctx.diagnostics.diagnostics)")
        #expect(!errors.contains("KSWIFTK-MPP-UNRESOLVED"), "Expected both receiver-specific actuals to match: \(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        let ktorPackage = ["io", "ktor", "utils", "io", "charsets"]
        let expectEncoder = try propertySymbol("charset", flag: .expectDeclaration, packageComponents: ktorPackage, in: ctx)
        let expectDecoder = try propertySymbol("charset", flag: .expectDeclaration, excluding: expectEncoder.id, packageComponents: ktorPackage, in: ctx)
        let actualEncoder = try propertySymbol("charset", flag: .actualDeclaration, receiver: "CharsetEncoder", packageComponents: ktorPackage, in: ctx)
        let actualDecoder = try propertySymbol("charset", flag: .actualDeclaration, receiver: "CharsetDecoder", packageComponents: ktorPackage, in: ctx)
        #expect(sema.symbols.actualSymbol(for: expectEncoder.id) == actualEncoder.id)
        #expect(sema.symbols.actualSymbol(for: expectDecoder.id) == actualDecoder.id)
    }

    @Test func testDifferentReceiverDoesNotMatch() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect class Encoder
            expect class Decoder
            expect val Encoder.label: Int
            """,
            """
            package sample.kmp
            actual class Encoder
            actual class Decoder
            actual val Decoder.label: Int = 1
            """,
        ])
        try runSema(ctx)

        let errors = errorCodes(in: ctx)
        #expect(errors.contains("KSWIFTK-MPP-UNRESOLVED"), "Receiver mismatch should leave the expect unresolved: \(ctx.diagnostics.diagnostics)")
        #expect(!errors.contains("KSWIFTK-MPP-AMBIGUOUS"), "A receiver mismatch is not a duplicate match: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testExtensionAndNonExtensionPropertiesDoNotMatch() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect val String.extensionOnly: Int
            expect val regularOnly: Int
            """,
            """
            package sample.kmp
            actual val extensionOnly: Int = 1
            actual val String.regularOnly: Int = 2
            """,
        ])
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-MPP-UNRESOLVED" }.count == 2, "Both receiver-presence mismatches should be unresolved: \(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-MPP-AMBIGUOUS" }, "Receiver-presence mismatch should not be ambiguous: \(errors)")
    }

    @Test func testNullableAndGenericReceiverTypesAreCompared() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect class Box<T>
            // Separate '?' and '.' so this parser treats the nullable receiver as a type suffix.
            expect val Box<String> ? .nullableMatch: Int
            expect val Box<String>.genericMatch: Int
            expect val Box<String> ? .nullabilityMismatch: Int
            expect val Box<String>.genericMismatch: Int
            """,
            """
            package sample.kmp
            actual class Box<T>
            actual val Box<String> ? .nullableMatch: Int = 1
            actual val Box<String>.genericMatch: Int = 2
            actual val Box<String>.nullabilityMismatch: Int = 3
            actual val Box<Int>.genericMismatch: Int = 4
            """,
        ])
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        for name in ["nullableMatch", "genericMatch"] {
            let expect = try propertySymbol(name, flag: .expectDeclaration, in: ctx)
            let actual = try propertySymbol(name, flag: .actualDeclaration, in: ctx)
            #expect(sema.symbols.actualSymbol(for: expect.id) == actual.id, "Expected \(name) to link")
        }
        for name in ["nullabilityMismatch", "genericMismatch"] {
            let expect = try propertySymbol(name, flag: .expectDeclaration, in: ctx)
            #expect(sema.symbols.actualSymbol(for: expect.id) == nil, "Expected \(name) receiver mismatch to remain unresolved")
        }
        #expect(errorCodes(in: ctx).filter { $0 == "KSWIFTK-MPP-UNRESOLVED" }.count == 2, "Expected only the two receiver mismatches to be unresolved: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testMutableAndPropertyTypeMismatchesRemainUnresolved() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect val mutableMismatch: Int
            expect val typeMismatch: String
            """,
            """
            package sample.kmp
            actual var mutableMismatch: Int = 1
            actual val typeMismatch: Int = 1
            """,
        ])
        try runSema(ctx)

        let unresolvedCount = errorCodes(in: ctx).filter { $0 == "KSWIFTK-MPP-UNRESOLVED" }.count
        #expect(unresolvedCount == 2, "Mutability and property-type mismatches must still reject candidates: \(ctx.diagnostics.diagnostics)")
    }

    @Test func testDuplicateActualsWithMatchingReceiverRemainAmbiguous() throws {
        let ctx = makeContextFromSources([
            """
            package sample.kmp
            expect val String.label: Int
            """,
            """
            package sample.kmp
            actual val String.label: Int = 1
            actual val String.label: Int = 2
            """,
        ])
        try runSema(ctx)

        #expect(errorCodes(in: ctx).contains("KSWIFTK-MPP-AMBIGUOUS"), "Matching duplicate actuals should remain ambiguous: \(ctx.diagnostics.diagnostics)")
    }

    private func propertySymbol(
        _ name: String,
        flag: SymbolFlags,
        excluding excluded: SymbolID? = nil,
        receiver: String? = nil,
        packageComponents: [String] = ["sample", "kmp"],
        in ctx: CompilationContext
    ) throws -> SemanticSymbol {
        let sema = try #require(ctx.sema)
        let fqName = (packageComponents + [name]).map(ctx.interner.intern)
        let candidates = sema.symbols.lookupAll(fqName: fqName)
            .compactMap { sema.symbols.symbol($0) }
            .filter { symbol in
                symbol.kind == .property
                    && symbol.flags.contains(flag)
                    && symbol.id != excluded
            }
        if let receiver {
            return try #require(candidates.first { candidate in
                guard let receiverType = sema.symbols.extensionPropertyReceiverType(for: candidate.id),
                      case let .classType(classType) = sema.types.kind(of: receiverType),
                      let receiverSymbol = sema.symbols.symbol(classType.classSymbol)
                else {
                    return false
                }
                return ctx.interner.resolve(receiverSymbol.name) == receiver
            })
        }
        return try #require(
            candidates.first,
            "Missing \(flag) property symbol for \((packageComponents + [name]).joined(separator: ".")): \(ctx.diagnostics.diagnostics)"
        )
    }

    private func errorCodes(in ctx: CompilationContext) -> [String] {
        ctx.diagnostics.diagnostics
            .filter { $0.severity == .error }
            .compactMap(\.code)
    }
}
#endif
