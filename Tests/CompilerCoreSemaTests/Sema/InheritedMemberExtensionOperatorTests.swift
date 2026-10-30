#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct InheritedMemberExtensionOperatorTests {
    @Test
    func inheritedInterfaceMemberExtensionOperatorResolves() throws {
        let source = """
        package kuu2322

        interface Tag {
            operator fun String.unaryPlus() {}
        }

        class HtmlTag : Tag

        fun HtmlTag.render(content: String) {
            +content
            content.unaryPlus()
        }

        class OverridingHtmlTag : Tag {
            override operator fun String.unaryPlus() {}
        }

        fun OverridingHtmlTag.render(content: String) { +content }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let tagSymbol = try #require(
                sema.symbols.lookup(fqName: ["kuu2322", "Tag"].map(interner.intern))
            )
            let overrideSymbol = try #require(
                sema.symbols.lookup(fqName: ["kuu2322", "OverridingHtmlTag"].map(interner.intern))
            )
            let inheritedOperator = try #require(
                sema.symbols.lookup(fqName: ["kuu2322", "Tag", "unaryPlus"].map(interner.intern))
            )
            let overrideOperator = try #require(
                sema.symbols.lookup(fqName: ["kuu2322", "OverridingHtmlTag", "unaryPlus"].map(interner.intern))
            )

            let unaryExpressions = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .unaryExpr(op, _, range) = expression,
                      op == .unaryPlus,
                      ctx.sourceManager.path(of: range.start.file) == paths[0]
                else { return nil }
                return ExprID(rawValue: Int32(index))
            }
            #expect(unaryExpressions.count == 2)
            let bindings = try unaryExpressions.map { try #require(sema.bindings.callBindings[$0]) }
            #expect(bindings[0].chosenCallee == inheritedOperator)
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[0].chosenCallee) == tagSymbol)
            #expect(bindings[1].chosenCallee == overrideOperator)
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[1].chosenCallee) == overrideSymbol)
        }
    }

    @Test
    func topLevelOperatorStillResolves() throws {
        let source = """
        package kuu2322top

        operator fun String.unaryPlus() {}
        fun topLevel(content: String) { +content }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func unrelatedOrNonOperatorMemberExtensionsDoNotSatisfyUnaryOperator() throws {
        let source = """
        package kuu2322negative

        interface WrongReceiverTag {
            operator fun Int.unaryPlus() {}
        }
        class WrongReceiverHtmlTag : WrongReceiverTag

        interface NonOperatorTag {
            fun String.unaryPlus() {}
        }
        class NonOperatorHtmlTag : NonOperatorTag

        fun WrongReceiverHtmlTag.render(content: String) { +content }
        fun NonOperatorHtmlTag.render(content: String) { +content }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = diagnosticsForPath(paths[0], in: ctx).filter {
                $0.code == "KSWIFTK-SEMA-0002" && $0.severity == .error
            }
            #expect(errors.count == 2, "Expected both invalid operators to be rejected: \(errors)")
        }
    }
}
#endif
