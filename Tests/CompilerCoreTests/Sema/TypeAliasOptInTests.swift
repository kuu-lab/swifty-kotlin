@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeAliasOptInTests {
    @Test(arguments: [false, true], ["WARNING", "ERROR"])
    func typeUsesAndDirectConstructorsRequireOptIn(usingKklib: Bool, level: String) throws {
        let source = """
        @RequiresOptIn(level = RequiresOptIn.Level.\(level))
        @Target(AnnotationTarget.CLASS, AnnotationTarget.TYPEALIAS)
        annotation class Marker
        @Marker class Box
        typealias UnoptedAlias = Box
        @OptIn(Marker::class) typealias Alias = Box
        fun inferred() { Alias() }
        fun typed(): Alias = Alias()
        fun direct() { Box() }
        val typedValue: Box = Box()
        @OptIn(Marker::class) fun safe(): Alias = Box()
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 5, "\(diagnostics)")
        #expect(diagnostics.allSatisfy {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("Marker")
                && $0.severity == (level == "ERROR" ? .error : .warning)
        })
        let expectedSites = [
            "typealias UnoptedAlias", "fun typed", "Box() }",
            "val typedValue", "Box()\n@OptIn",
        ]
        let expectedOffsets = try expectedSites.map { site in
            let start = try #require(source.range(of: site)).lowerBound
            return source[..<start].utf8.count
        }
        #expect(Set(diagnostics.compactMap { $0.primaryRange?.start.offset }) == Set(expectedOffsets))
    }

    @Test(arguments: [false, true])
    func aliasAndConstructorMarkersRemainRequired(usingKklib: Bool) throws {
        let source = """
        @RequiresOptIn
        @Target(AnnotationTarget.CLASS, AnnotationTarget.TYPEALIAS)
        annotation class ClassMarker
        @RequiresOptIn
        @Target(AnnotationTarget.CONSTRUCTOR)
        annotation class ConstructorMarker
        @ClassMarker class Box @ConstructorMarker constructor()
        @OptIn(ClassMarker::class) typealias Alias = Box
        @OptIn(ClassMarker::class) typealias Chain = Alias
        @ClassMarker typealias MarkedAlias = Box
        fun aliasCall() { Alias() }
        fun chainCall() { Chain() }
        fun markedCall() { MarkedAlias() }
        fun directCall() { Box() }
        @OptIn(ClassMarker::class, ConstructorMarker::class)
        fun safe() { Alias(); Chain(); MarkedAlias(); Box() }
        """
        let context = try check(source, usingKklib: usingKklib)
        let diagnostics = context.diagnostics.diagnostics
        #expect(diagnostics.count == 6, "\(diagnostics)")
        #expect(diagnostics.allSatisfy { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error })
        #expect(diagnostics.filter { $0.message.contains("'ClassMarker'") }.count == 2)
        #expect(diagnostics.filter { $0.message.contains("'ConstructorMarker'") }.count == 4)
    }

    private func check(_ source: String, usingKklib: Bool) throws -> CompilationContext {
        if usingKklib {
            TestStdlibCache.shared.prepare()
            let path = try #require(CompilerOptions.defaultStdlibLibraryPath)
            try #require(FileManager.default.fileExists(atPath: path + "/manifest.json"))
        }
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let context = makeCompilationContext(
            inputs: [path],
            includeStdlib: usingKklib,
            allowDefaultStdlibLibrary: usingKklib
        )
        _ = context.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runSema(context)
        return context
    }
}
