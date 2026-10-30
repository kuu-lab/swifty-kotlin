#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testAnnotationTargetFactoryRetainsEnumNameHelpersAcrossRetentions() throws {
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let fixture = try String(contentsOf: repository.appendingPathComponent(
            "Scripts/diff_cases/annotation_target_metadata_factory.kt"
        ), encoding: .utf8)
        let main = try #require(fixture.range(of: "fun main() {"))
        let source = String(fixture[..<main.lowerBound]) + "fun main() {}"
        try assertAnnotationFactoryEnumDependencies(source, enumNames: ["AnnotationTarget", "AnnotationRetention"])
    }

    @Test
    func testExpressionTargetFactoryRetainsEnumNameHelper() throws {
        try assertAnnotationFactoryEnumDependencies("""
        @Target(AnnotationTarget.EXPRESSION)
        @Retention(AnnotationRetention.SOURCE)
        annotation class Tag
        fun main() {}
        """, enumNames: ["AnnotationTarget"])
    }

    @Test
    func testUnannotatedKIRDoesNotRetainAnnotationEnumNameHelpers() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            let helperNames = module.arena.declarations.compactMap { declaration -> String? in
                guard case let .function(function) = declaration else { return nil }
                return ctx.interner.resolve(function.name)
            }
            #expect(!helperNames.contains { $0.hasPrefix("$enumOrdinalToName$") && $0.contains("AnnotationTarget") })
            #expect(!helperNames.contains { $0.hasPrefix("$enumOrdinalToName$") && $0.contains("AnnotationRetention") })
        }
    }

    private func assertAnnotationFactoryEnumDependencies(_ source: String, enumNames: [String]) throws {
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let functions = module.arena.declarations.compactMap { declaration -> KIRFunction? in
                guard case let .function(function) = declaration else { return nil }
                return function
            }
            for enumName in enumNames {
                let owner = try #require(sema.symbols.lookup(fqName: ["kotlin", "annotation", enumName].map(ctx.interner.intern)))
                let helperName = NameMangler.enumOrdinalToNameHelperName(
                    for: try #require(sema.symbols.symbol(owner)), interner: ctx.interner
                )
                #expect(functions.contains { function in
                    ctx.interner.resolve(function.name).hasPrefix("$annotationFactory$") && function.body.contains {
                        if case let .call(_, callee, _, _, _, _, _, _) = $0 { return callee == helperName }
                        return false
                    }
                })
                let helper = try #require(functions.first { $0.name == helperName })
                #expect(!helper.body.isEmpty)
            }
            #expect(KIRVerifier.verify(module: module, symbols: sema.symbols, interner: ctx.interner).isEmpty)
        }
    }
}
#endif
