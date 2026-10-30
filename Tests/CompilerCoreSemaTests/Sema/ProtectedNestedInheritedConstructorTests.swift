@testable import CompilerCore
import Foundation
import TestStdlibCache
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct ProtectedNestedInheritedConstructorTests {
    @Test
    func sourceModeAllowsOwnerAndSubclassToCallInheritedProtectedConstructor() throws {
        try checkValidAccess(fromSource: true, optimization: 0)
    }

    @Test(arguments: [0, 2])
    func stdlibArtifactAllowsOwnerAndSubclassToCallInheritedProtectedConstructor(optimization: Int) throws {
        try checkValidAccess(fromSource: false, optimization: optimization)
    }

    @Test(arguments: [false, true])
    func inaccessibleProtectedAccessAndExplicitConstructorStayRejected(fromSource: Bool) throws {
        let source = """
        open class CommonMarkdownConstraints {
            protected data class ListMarkerInfo(val markerLength: Int, val markerType: Char)
        }

        class GfmConstraints : CommonMarkdownConstraints() {
            fun fromSubclass(): Int =
                CommonMarkdownConstraints.ListMarkerInfo(2, '*').markerLength
        }

        open class ExplicitOwner {
            data class Explicit protected constructor(val value: Int)
            fun fromOwner(): Int = Explicit(1).value
        }

        class ExplicitOwnerChild : ExplicitOwner() {
            fun fromSubclass(): Int = ExplicitOwner.Explicit(2).value
        }

        class Unrelated {
            fun fromUnrelated(): Int = CommonMarkdownConstraints.ListMarkerInfo(3, '!').markerLength
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = try makeSemaContext(
                inputs: paths,
                fromSource: fromSource,
                optimization: 0
            )
            try runSema(context)

            let protectedErrors = context.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code == "KSWIFTK-SEMA-0041"
            }
            #expect(protectedErrors.filter { $0.message.contains("'ListMarkerInfo'") }.count == 1, "\(protectedErrors)")
            #expect(protectedErrors.filter { $0.message.contains("'Explicit'") }.count == 2, "\(protectedErrors)")
        }
    }

    private func checkValidAccess(fromSource: Bool, optimization: Int) throws {
        let source = """
        open class CommonMarkdownConstraints {
            protected data class ListMarkerInfo(val markerLength: Int, val markerType: Char)

            fun fromOwner(): Int = ListMarkerInfo(1, '-').markerLength
        }

        class GfmConstraints : CommonMarkdownConstraints() {
            fun fromSubclass(): Int =
                CommonMarkdownConstraints.ListMarkerInfo(2, '*').markerLength
        }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let context = try makeSemaContext(
                inputs: paths,
                fromSource: fromSource,
                optimization: optimization
            )
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
        }
    }

    private func makeSemaContext(
        inputs: [String],
        fromSource: Bool,
        optimization: Int
    ) throws -> CompilationContext {
        if !fromSource {
            TestStdlibCache.shared.prepare()
        }
        let options = CompilerOptions(
            moduleName: "ProtectedNestedInheritedConstructor",
            inputs: inputs,
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple(),
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            includeStdlib: true,
            stdlibLibraryPath: fromSource ? nil : CompilerOptions.defaultStdlibLibraryPath,
            allowDefaultStdlibLibrary: false
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
    }
}
