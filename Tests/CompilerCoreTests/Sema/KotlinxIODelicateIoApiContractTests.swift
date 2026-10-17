#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
import TestStdlibCache

@Suite(.serialized)
struct KotlinxIODelicateIoApiContractTests {
    private let delicateApiMessage = "This is a delicate API and its use requires care. "
        + "Make sure you fully read and understand documentation of the declaration that is marked as a delicate API."

    private func compileConsumer(usesLibrary: Bool) throws -> CompilationContext {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let input = directory.appendingPathComponent("DelicateIoApiConsumer.kt")
        try """
        package delicate.consumer
        import kotlinx.io.DelicateIoApi

        @DelicateIoApi
        fun markedOperation(): String = "delicate"

        @OptIn(DelicateIoApi::class)
        fun optedInConsumer(): String = markedOperation()

        fun unoptedConsumer(): String = markedOperation()
        """.write(to: input, atomically: true, encoding: .utf8)

        let libraryPath: String?
        if usesLibrary {
            TestStdlibCache.shared.prepare()
            libraryPath = CompilerOptions.defaultStdlibLibraryPath
        } else {
            libraryPath = nil
        }

        let context = makeCompilationContext(
            inputs: [input.path],
            moduleName: "KotlinxIoDelicateIoApiConsumer",
            emit: .executable,
            stdlibLibraryPath: libraryPath,
            allowDefaultStdlibLibrary: usesLibrary
        )
        try runSema(context)
        return context
    }

    @Test(arguments: [false, true])
    func declarationMetadataAndOptInDiagnosticsSurviveSourceAndLibraryViews(usesLibrary: Bool) throws {
        let context = try compileConsumer(usesLibrary: usesLibrary)
        let sema = try #require(context.sema)
        let markerName = ["kotlinx", "io", "DelicateIoApi"].map(context.interner.intern)
        let markerID = try #require(sema.symbols.lookup(fqName: markerName))
        let marker = try #require(sema.symbols.symbol(markerID))
        #expect(marker.kind == .annotationClass)
        #expect(marker.visibility == .public)

        let initializerName = KnownCompilerNames(interner: context.interner).initName
        let constructors = sema.symbols.lookupAll(fqName: markerName + [initializerName])
            .compactMap { sema.symbols.symbol($0) }
            .filter { $0.kind == .constructor }
        let constructor = try #require(constructors.count == 1 ? constructors.first : nil)
        #expect(constructor.visibility == .public)
        #expect(constructor.flags.contains(.importedLibrary) == usesLibrary)
        let constructorSignature = try #require(sema.symbols.functionSignature(for: constructor.id))
        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: markerID,
            args: [],
            nullability: .nonNull
        )))
        #expect(constructorSignature.parameterTypes.isEmpty)
        #expect(constructorSignature.valueParameterHasDefaultValues.isEmpty)
        #expect(constructorSignature.valueParameterIsVararg.isEmpty)
        #expect(constructorSignature.receiverType == annotationType)
        #expect(constructorSignature.returnType == annotationType)

        let annotations = sema.symbols.annotations(for: markerID)
        #expect(annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" })
        #expect(annotations.contains {
            $0.annotationFQName == "kotlin.annotation.Retention"
                && $0.arguments.contains { $0.contains("BINARY") }
        })
        #expect(annotations.contains {
            $0.annotationFQName == "kotlin.RequiresOptIn"
                && $0.arguments.contains { $0.contains("WARNING") }
        })

        let optInDiagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }
        #expect(optInDiagnostics.count == 1, "Expected only the unopted consumer to be diagnosed: \(optInDiagnostics)")
        #expect(optInDiagnostics.first?.severity == .warning)
        #expect(optInDiagnostics.first?.message.contains(delicateApiMessage) == true)

        let source = """
        package delicate.consumer
        import kotlinx.io.DelicateIoApi

        @DelicateIoApi
        fun markedOperation(): String = "delicate"

        @OptIn(DelicateIoApi::class)
        fun optedInConsumer(): String = markedOperation()

        fun unoptedConsumer(): String = markedOperation()
        """
        let unoptedLine = source.components(separatedBy: "\n").firstIndex {
            $0.contains("fun unoptedConsumer")
        }.map { $0 + 1 }
        let diagnosticLine = optInDiagnostics.first?.primaryRange.map {
            context.sourceManager.lineColumn(of: $0.start).line
        }
        #expect(diagnosticLine == unoptedLine)
    }
}
#endif
