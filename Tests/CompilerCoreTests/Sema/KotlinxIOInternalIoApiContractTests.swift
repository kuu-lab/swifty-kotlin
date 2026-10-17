#if canImport(Testing)
@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing

@Suite
struct KotlinxIOInternalIoApiContractTests {
    private func context(_ source: String) throws -> CompilationContext {
        let artifact: String
        if let suppliedArtifact = ProcessInfo.processInfo.environment["KSWIFTK_INTERNAL_IO_API_STDLIB_KLIB"] {
            artifact = URL(fileURLWithPath: suppliedArtifact).standardizedFileURL.path
            #expect(FileManager.default.fileExists(atPath: artifact))
        } else {
            TestStdlibCache.shared.prepare()
            artifact = try #require(CompilerOptions.defaultStdlibLibraryPath)
        }
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(
            inputs: [path],
            stdlibLibraryPath: artifact,
            allowDefaultStdlibLibrary: false
        )
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try #require(context.options.stdlibLibraryPath == artifact)
        #expect(!context.options.includeStdlib)
        return context
    }

    private func decodedStringArgument(_ name: String, in arguments: [String]) throws -> String {
        let prefix = name + "=\""
        let value = try #require(arguments.joined(separator: " ").range(of: prefix))
        let encoded = arguments.joined(separator: " ")[value.upperBound...]
        let end = try #require(encoded.firstIndex(of: "\""))
        let json = "\"" + encoded[..<end] + "\""
        return try JSONDecoder().decode(String.self, from: Data(json.utf8))
    }

    @Test
    func declarationRetentionConstructorAndOptInSurviveFreshKlib() throws {
        let context = try context("""
        package kuu2614
        import kotlinx.io.Buffer
        import kotlinx.io.InternalIoApi

        @OptIn(InternalIoApi::class)
        @InternalIoApi
        fun markedWithInternalIoApi() {}

        fun withoutOptIn(buffer: Buffer) {
            buffer.hintEmit()
        }

        @OptIn(InternalIoApi::class)
        fun withOptIn(buffer: Buffer) {
            buffer.hintEmit()
        }
        """)
        try runSema(context)

        let diagnostics = context.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-OPT-IN" }
        try #require(diagnostics.count == 1, "Expected one direct InternalIoApi opt-in diagnostic: \(context.diagnostics.diagnostics)")
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].message.contains("InternalIoApi"))
        let input = try #require(context.options.inputs.first)
        let range = try #require(diagnostics[0].primaryRange)
        #expect(context.sourceManager.path(of: range.start.file) == input)
        #expect(context.sourceManager.lineColumn(of: range.start).line == 10)

        let sema = try #require(context.sema)
        let symbols = sema.symbols
        let interner = context.interner
        let markerID = try #require(symbols.lookup(fqName: ["kotlinx", "io", "InternalIoApi"].map(interner.intern)))
        let marker = try #require(symbols.symbol(markerID))
        #expect(marker.kind == .annotationClass)
        #expect(marker.visibility == .public)
        #expect(marker.flags.contains(.importedLibrary))

        let annotations = symbols.annotations(for: markerID)
        #expect(Set(annotations.map(\.annotationFQName)) == [
            "kotlin.Metadata",
            "kotlin.RequiresOptIn",
            "kotlin.annotation.MustBeDocumented",
            "kotlin.annotation.Retention",
        ])
        let retention = try #require(annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" })
        #expect(retention.arguments == ["AnnotationRetention.BINARY"])
        let documented = try #require(annotations.first { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
        #expect(documented.arguments.isEmpty)
        let requiresOptIn = try #require(annotations.first { $0.annotationFQName == "kotlin.RequiresOptIn" })
        #expect(requiresOptIn.arguments.contains { $0.contains("RequiresOptIn.Level.ERROR") })
        #expect(try decodedStringArgument("message", in: requiresOptIn.arguments) ==
            "This is an internal API and its use requires care. It is subject to change or removal and is not intended for use outside the library.Make sure you fully read and understand documentation of the declaration that is marked as an internal API.")

        let constructorIDs = symbols.lookupAll(
            fqName: ["kotlinx", "io", "InternalIoApi", "<init>"].map(interner.intern)
        ).filter { symbols.symbol($0)?.kind == .constructor }
        try #require(constructorIDs.count == 1, "InternalIoApi must expose exactly one implicit no-argument constructor")
        let constructor = try #require(symbols.symbol(constructorIDs[0]))
        let signature = try #require(symbols.functionSignature(for: constructor.id))
        #expect(constructor.visibility == .public)
        #expect(constructor.flags.contains(.importedLibrary))
        #expect(signature.parameterTypes.isEmpty)
        #expect(signature.valueParameterHasDefaultValues.isEmpty)
        #expect(signature.returnType == sema.types.make(.classType(ClassType(
            classSymbol: markerID,
            args: [],
            nullability: .nonNull
        ))))

        let markedID = try #require(symbols.lookup(fqName: ["kuu2614", "markedWithInternalIoApi"].map(interner.intern)))
        let appliedMarker = symbols.annotations(for: markedID).filter {
            $0.annotationFQName == "kotlinx.io.InternalIoApi"
        }
        #expect(appliedMarker.count == 1, "Applying the marker must resolve through its implicit constructor")

        let libraryPath = URL(fileURLWithPath: try #require(context.options.stdlibLibraryPath))
        let records = MetadataDecoder().decode(try Data(contentsOf: libraryPath.appendingPathComponent("metadata.bin")))
        #expect(records.contains { $0.fqName == "kotlinx.io.InternalIoApi" && $0.kind == .annotationClass })
        #expect(records.contains {
            $0.fqName == "kotlinx.io.InternalIoApi.<init>"
                && $0.kind == .constructor
                && $0.typeSignature?.contains("InternalIoApi") == true
        })
    }
}
#endif
