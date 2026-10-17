#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KotlinxIOUnsafeByteStringApiContractTests {
    private let markerName = "kotlinx.io.bytestring.unsafe.UnsafeByteStringApi"
    private let unsafeMessage = "This is a unsafe API and its use may corrupt the data stored in a byte string. "
        + "Make sure you fully read and understand documentation of the declaration that is marked as an unsafe API."

    private func context(_ source: String, library: Bool) throws -> CompilationContext {
        if library { TestStdlibCache.shared.prepare() }
        let selectedLibrary = library
            ? try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib artifact must be published") : nil
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let result = makeCompilationContext(
            inputs: [inputPath],
            stdlibLibraryPath: selectedLibrary,
            allowDefaultStdlibLibrary: false
        )
        _ = result.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        #expect(result.options.stdlibLibraryPath == selectedLibrary)
        #expect(result.options.includeStdlib == !library)
        return result
    }

    private func isAnnotated(_ symbol: SymbolID, _ annotationName: String, in table: SymbolTable) -> Bool {
        table.annotations(for: symbol).contains {
            $0.annotationFQName == annotationName || $0.annotationFQName.hasSuffix("." + annotationName)
        }
    }

    @Test(arguments: [false, true])
    func annotationShapeAndOptInDiagnosticsMatchSourceAndLibrary(library: Bool) throws {
        let source = """
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringApi
        import kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations

        fun withoutOptIn(bytes: ByteArray) = UnsafeByteStringOperations.wrapUnsafe(bytes)

        @OptIn(UnsafeByteStringApi::class)
        @UnsafeByteStringApi
        class MarkedUnsafeDeclaration

        @OptIn(UnsafeByteStringApi::class)
        fun withOptIn(bytes: ByteArray) = UnsafeByteStringOperations.wrapUnsafe(bytes)
        """
        let ctx = try context(source, library: library)
        try? runSema(ctx)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        #expect(optInDiagnostics.count == 2,
                "The unannotated object and method references each retain the upstream opt-in error: \(ctx.diagnostics.diagnostics)")
        #expect(optInDiagnostics.allSatisfy { $0.severity == .error })
        #expect(optInDiagnostics.allSatisfy { $0.message.contains("UnsafeByteStringApi") })
        #expect(optInDiagnostics.allSatisfy { $0.message.contains(unsafeMessage) })
        let withoutOptInLine = source.components(separatedBy: "\n")
            .firstIndex { $0.hasPrefix("fun withoutOptIn") }.map { $0 + 1 }
        let withOptInLine = source.components(separatedBy: "\n").firstIndex { $0.hasPrefix("fun withOptIn") }.map { $0 + 1 }
        let diagnosticLines = Set(optInDiagnostics.compactMap { diagnostic -> Int? in
            guard let range = diagnostic.primaryRange else { return nil }
            return ctx.sourceManager.lineColumn(of: range.start).line
        })
        #expect(ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            .allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" })
        if let withoutOptInLine, let withOptInLine, let sema = ctx.sema {
            #expect(diagnosticLines == [withoutOptInLine], "Both diagnostics should point to the rejected call")
            #expect(!diagnosticLines.contains(withOptInLine), "The explicitly opted-in call should not be diagnosed")
            let symbols = sema.symbols
            let markerPath = markerName.split(separator: ".").map { ctx.interner.intern(String($0)) }
            let markerID = try #require(symbols.lookupAll(fqName: markerPath).first {
                symbols.symbol($0)?.kind == .annotationClass
            })
            let marker = try #require(symbols.symbol(markerID))
            #expect(marker.visibility == .public)
            #expect(marker.flags.contains(.importedLibrary) == library)
            #expect(isAnnotated(markerID, "MustBeDocumented", in: symbols))

            let markerAnnotations = symbols.annotations(for: markerID)
            #expect(markerAnnotations.contains {
                $0.annotationFQName.hasSuffix("Retention") && $0.arguments.joined().contains("BINARY")
            })
            let requiresOptIn = try #require(markerAnnotations.first { $0.annotationFQName.hasSuffix("RequiresOptIn") })
            #expect(requiresOptIn.arguments.joined().contains("ERROR"))
            let message = try #require(requiresOptIn.arguments.first { $0.hasPrefix("message=") })
            #expect(message.dropFirst("message=".count).replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "+", with: "") == unsafeMessage)

            let ownerType = sema.types.make(.classType(ClassType(classSymbol: markerID, args: [], nullability: .nonNull)))
            let constructors = symbols.lookupAll(fqName: markerPath + [ctx.interner.intern("<init>")])
                .compactMap { symbols.symbol($0) }.filter { $0.kind == .constructor }
            try #require(constructors.count == 1, "UnsafeByteStringApi has one public no-argument constructor")
            let constructor = try #require(constructors.first)
            let signature = try #require(symbols.functionSignature(for: constructor.id))
            #expect(constructor.visibility == .public)
            #expect(constructor.flags.contains(.importedLibrary) == library)
            #expect(signature.receiverType == ownerType && signature.returnType == ownerType)
            #expect(signature.parameterTypes.isEmpty)
            #expect(signature.valueParameterHasDefaultValues.isEmpty)
            #expect(signature.valueParameterIsVararg.isEmpty)

            let operations = try #require(symbols.lookupAll(fqName:
                "kotlinx.io.bytestring.unsafe.UnsafeByteStringOperations".split(separator: ".")
                    .map { ctx.interner.intern(String($0)) }).first {
                        symbols.symbol($0)?.kind == .object
                    })
            #expect(isAnnotated(operations, "UnsafeByteStringApi", in: symbols))
        } else {
            Issue.record("Sema must retain symbols for the opt-in contract probe")
        }
    }
}
#endif
