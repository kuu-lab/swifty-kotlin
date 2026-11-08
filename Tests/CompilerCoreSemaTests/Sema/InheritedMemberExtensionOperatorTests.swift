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

    @Test
    func inheritedInterfaceMemberExtensionBinaryOperatorResolves() throws {
        let source = """
        package kuu4420

        interface Ring<T> {
            operator fun T.plus(arg: T): T = arg
            operator fun T.times(arg: T): T = arg
        }

        class V(val x: Int)

        class VRing : Ring<V> {
            override operator fun V.plus(arg: V): V = arg
            override operator fun V.times(arg: V): V = arg

            fun combine(a: V, b: V): V = a + b
            fun scale(a: V, b: V): V = a * b
        }

        fun <T> Ring<T>.genericCombine(a: T, b: T): T = a + b
        fun <T> Ring<T>.genericScale(a: T, b: T): T = a * b
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let ringSymbol = try #require(
                sema.symbols.lookup(fqName: ["kuu4420", "Ring"].map(interner.intern))
            )
            let vringSymbol = try #require(
                sema.symbols.lookup(fqName: ["kuu4420", "VRing"].map(interner.intern))
            )

            let binaryExpressions = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .binary(op, _, _, range) = expression,
                      [.add, .multiply].contains(op),
                      ctx.sourceManager.path(of: range.start.file) == paths[0]
                else { return nil }
                return ExprID(rawValue: Int32(index))
            }
            #expect(binaryExpressions.count == 4)
            let bindings = try binaryExpressions.map { try #require(sema.bindings.callBindings[$0]) }
            // Member lookups resolve the innermost applicable member extension:
            // VRing's overrides inside its own members, Ring's declarations in
            // the generic extension functions.
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[0].chosenCallee) == vringSymbol)
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[1].chosenCallee) == vringSymbol)
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[2].chosenCallee) == ringSymbol)
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: bindings[3].chosenCallee) == ringSymbol)
            #expect(bindings.allSatisfy {
                sema.symbols.symbol($0.chosenCallee)?.flags.contains(.operatorFunction) == true
            })
        }
    }

    @Test
    func memberExtensionOperatorDoesNotShadowPackageExtensionForOtherReceivers() throws {
        let source = """
        package kuu4420shadow

        interface Ring<T> {
            operator fun T.plus(arg: T): T
        }

        class Foo
        operator fun Foo.plus(arg: Foo): Foo = arg

        class IntRing : Ring<Int> {
            override operator fun Int.plus(arg: Int): Int = arg

            // `Int.plus` member extension must not capture `Foo` operands.
            fun combine(a: Foo, b: Foo): Foo = a + b
        }

        // The generic `T.plus` member extension is permissively collected for
        // `Foo` operands but must lose viability to the package extension.
        fun <T> Ring<T>.genericShadow(a: Foo, b: Foo): Foo = a + b
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let packagePlus = try #require(
                sema.symbols.lookup(fqName: ["kuu4420shadow", "plus"].map(interner.intern))
            )
            let binaryExpressions = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .binary(.add, _, _, range) = expression,
                      ctx.sourceManager.path(of: range.start.file) == paths[0]
                else { return nil }
                return ExprID(rawValue: Int32(index))
            }
            #expect(binaryExpressions.count == 2)
            for expr in binaryExpressions {
                let binding = try #require(sema.bindings.callBindings[expr])
                #expect(binding.chosenCallee == packagePlus)
            }
        }
    }

    @Test
    func memberExtensionCompoundAssignResolvesThroughBinaryOperator() throws {
        let source = """
        package kuu4420assign

        interface Ring<T> {
            operator fun T.plus(arg: T): T
        }

        fun <T> Ring<T>.accumulate(a: T, b: T): T {
            var sum = a
            sum += b
            return sum
        }
        """

        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let ringSymbol = try #require(
                sema.symbols.lookup(fqName: ["kuu4420assign", "Ring"].map(interner.intern))
            )
            let ast = try #require(ctx.ast)
            let assignExpressions = ast.arena.exprs.enumerated().compactMap { index, expression -> ExprID? in
                guard case let .compoundAssign(_, _, _, range) = expression,
                      ctx.sourceManager.path(of: range.start.file) == paths[0]
                else { return nil }
                return ExprID(rawValue: Int32(index))
            }
            let binding = try #require(assignExpressions.first.flatMap { sema.bindings.callBindings[$0] })
            #expect(sema.symbols.memberExtensionOwnerSymbol(for: binding.chosenCallee) == ringSymbol)
        }
    }
}
#endif
