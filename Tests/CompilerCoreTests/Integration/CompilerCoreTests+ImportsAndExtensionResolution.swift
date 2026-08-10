#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {

    @Test func testImportsAndExtensionResolution() throws {
        let sources: [String] = [
            // testCallRejectsSpreadForNonVarargParameter
            """
            package sample0
                    fun take(x: Int) = x
                    fun use() = take(*1)

            """,

            // testSemaAllowsOverloadedTopLevelFunctionsWithoutDuplicateDiagnostic
            """
            package sample1
                    fun pick(x: Int) = x
                    fun pick(x: String) = x
                    fun use() = pick(1)

            """,

            // testUnqualifiedCallPrefersImplicitReceiverMemberOverForeignExtension
            """
            package sample2
                    class Counter(var value: Int) {
                        fun compareAndSet(expected: Int, newValue: Int): Boolean = true
                    }
                    class Flag(var raised: Boolean)
                    fun Flag.compareAndSet(expected: Boolean, newValue: Boolean): Boolean = true
                    fun Counter.bump(): Boolean = compareAndSet(value, value + 1)

            """,

            // testInferredExpressionBodyReturnTypeCanFlowIntoTypedCall
            """
            package sample3
                    fun foo() = 1
                    fun takesInt(a: Int) = a
                    fun bar() = takesInt(foo())

            """,

            // testSemaResolvesNullableReceiverExtensionWithoutSafeCall
            """
            package sample4
                    fun String?.isNullOrEmpty(): Boolean = this == null || this.length == 0

                    fun useNullableReceiver(s: String?): Int {
                        val fromNullable = s.isNullOrEmpty()
                        val fromNullLiteral = null.isNullOrEmpty()
                        return if (fromNullable || fromNullLiteral) 1 else 0
                    }

            """,

            // testSemaResolvesUnqualifiedExtensionCallWithImplicitReceiver
            """
            package sample5
                    fun String.ext() = 1
                    fun String.wrap() = ext()

            """,

            // testGenericIdentityFunctionIsInferredAtCallSite
            """
            package sample6
                    fun <T> id(x: T): T = x
                    fun takesInt(a: Int) = a
                    fun main() = takesInt(id(1))

            """,

            // testGenericConstraintFailureReportsTypeDiagnostic
            """
            package sample7
                    fun <T> id(x: T): T = x
                    fun bad(): Boolean = id(1)

            """,

            // testImportAliasUnresolvedPathDiagnostic
            """
            package sample8
                    package app
                    import nonexistent.Thing as X
                    fun use() = 1

            """,

            // testImportAliasEmptyAliasNameIsIgnored
            """
            package sample9
                    package app
                    import kotlin.io.println as
                    fun use() = 1

            """,

            // testBuildASTParsesExtensionFunctionReceiverType
            """
            package sample10
            fun String.echo(): String = this
            """,

            // testBuildASTParsesNullableExtensionFunctionReceiverType
            """
            package sample11
            fun String?.echoNullable(): String = this ?: ""
            """,

            // testBuildASTParsesClassTypeParameterVariance
            """
            package sample12
            class Box<out T, in U, V>
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testCallRejectsSpreadForNonVarargParameter

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testSemaAllowsOverloadedTopLevelFunctionsWithoutDuplicateDiagnostic

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testUnqualifiedCallPrefersImplicitReceiverMemberOverForeignExtension

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }
            // testInferredExpressionBodyReturnTypeCanFlowIntoTypedCall

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testSemaResolvesNullableReceiverExtensionWithoutSafeCall

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0051", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)

            }
            // testSemaResolvesUnqualifiedExtensionCallWithImplicitReceiver

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testGenericIdentityFunctionIsInferredAtCallSite

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testGenericConstraintFailureReportsTypeDiagnostic

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sampleDiags)

            }
            // testImportAliasUnresolvedPathDiagnostic

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: sampleDiags)

            }
            // testImportAliasEmptyAliasNameIsIgnored

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        // Parser should insert missing token; alias with empty name is skipped
                        assertNoDiagnostic("KSWIFTK-SEMA-0022", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sampleDiags)

            }

            let ast = try #require(ctx.ast)
            let sourceFileIDs = try paths.map { path in
                try #require(ctx.sourceManager.fileID(forPath: path))
            }

            // testBuildASTParsesExtensionFunctionReceiverType
            do {
                let file = try #require(ast.files.first { $0.fileID == sourceFileIDs[10] })
                let declID = try #require(file.topLevelDecls.first)
                let decl = try #require(ast.arena.decl(declID))
                guard case let .funDecl(funDecl) = decl else {
                    Issue.record("Expected function declaration")
                    return
                }

                #expect(funDecl.name != .invalid)
                let receiverTypeID = try #require(funDecl.receiverType)
                let receiverType = try #require(ast.arena.typeRef(receiverTypeID))
                if case let .named(path, _, nullable) = receiverType {
                    #expect(!nullable)
                    #expect(path.count == 1)
                    #expect(ctx.interner.resolve(path[0]) == "String")
                } else {
                    Issue.record("Expected named receiver type")
                }
            }

            // testBuildASTParsesNullableExtensionFunctionReceiverType
            do {
                let file = try #require(ast.files.first { $0.fileID == sourceFileIDs[11] })
                let declID = try #require(file.topLevelDecls.first)
                let decl = try #require(ast.arena.decl(declID))
                guard case let .funDecl(funDecl) = decl else {
                    Issue.record("Expected function declaration")
                    return
                }

                let receiverTypeID = try #require(funDecl.receiverType)
                let receiverType = try #require(ast.arena.typeRef(receiverTypeID))
                if case let .named(path, _, nullable) = receiverType {
                    #expect(nullable)
                    #expect(path.count == 1)
                    #expect(ctx.interner.resolve(path[0]) == "String")
                } else {
                    Issue.record("Expected named receiver type")
                }
            }

            // testBuildASTParsesClassTypeParameterVariance
            do {
                let file = try #require(ast.files.first { $0.fileID == sourceFileIDs[12] })
                let declID = try #require(file.topLevelDecls.first)
                let decl = try #require(ast.arena.decl(declID))
                guard case let .classDecl(classDecl) = decl else {
                    Issue.record("Expected class declaration")
                    return
                }

                #expect(classDecl.typeParams.count == 3)
                #expect(classDecl.typeParams.map(\.variance) == [.out, .in, .invariant])
                #expect(classDecl.typeParams.map { ctx.interner.resolve($0.name) } == ["T", "U", "V"])
            }
        }
    }


    // MARK: - Cross-package top-level function and import-alias resolution

    /// Consolidates the multi-source import resolution tests into a single Sema run.
    /// Uses unique package names so the scenarios do not collide in one module.
    @Test func testCrossPackageImportAndAliasResolutionSema() throws {
        let sources: [String] = [
            // 0: same-package top-level function resolution
            """
            package demo0
            fun helper0(x: Int) = x
            """,
            """
            package demo0
            fun use0() = helper0(1)
            """,

            // 1: explicit import across packages
            """
            package lib1
            fun helper1(x: Int) = x
            """,
            """
            package app1
            import lib1.helper1
            fun use1() = helper1(1)
            """,

            // 2: import alias wildcard diagnostic
            """
            package lib2
            fun helper2(x: Int) = x
            """,
            """
            package app2
            import lib2 as L2
            fun use2() = 1
            """,

            // 3: import alias duplicate diagnostic
            """
            package lib3
            fun foo3(x: Int) = x
            fun bar3(x: Int) = x
            """,
            """
            package app3
            import lib3.foo3 as X3
            import lib3.bar3 as X3
            fun use3() = 1
            """,

            // 4: import alias resolves across packages
            """
            package lib4
            fun helper4(x: Int) = x
            """,
            """
            package app4
            import lib4.helper4 as h4
            fun use4() = h4(1)
            """,

            // 5: import alias return type is inferred
            """
            package lib5
            fun compute5(x: Int): Int = x + 1
            """,
            """
            package app5
            import lib5.compute5 as calc5
            fun use5(): Int = calc5(5)
            """,

            // 6: multiple distinct aliases in same file
            """
            package lib6
            fun foo6(x: Int) = x
            fun bar6(x: Int) = x + 1
            """,
            """
            package app6
            import lib6.foo6 as f6
            import lib6.bar6 as b6
            fun use6() = f6(1) + b6(2)
            """,

            // 7: alias coexists with non-aliased import
            """
            package lib7
            fun foo7(x: Int) = x
            fun bar7(x: Int) = x + 1
            """,
            """
            package app7
            import lib7.foo7 as f7
            import lib7.bar7
            fun use7() = f7(1) + bar7(2)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)

            // 0: same package
            do {
                let diags = diagnosticsForPath(paths[1], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)
            }

            // 1: explicit import
            do {
                let diags = diagnosticsForPath(paths[3], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)
            }

            // 2: wildcard alias diagnostic
            do {
                let diags = diagnosticsForPath(paths[5], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0022", in: diags)
            }

            // 3: duplicate alias diagnostic
            do {
                let diags = diagnosticsForPath(paths[7], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0023", in: diags)
            }

            // 4: alias resolves
            do {
                let diags = diagnosticsForPath(paths[9], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)
            }

            // 5: alias return type inferred
            do {
                let diags = diagnosticsForPath(paths[11], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)

                let use5Symbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .function && ctx.interner.resolve(symbol.name) == "use5"
                })?.id)
                let use5Signature = try #require(sema.symbols.functionSignature(for: use5Symbol))
                #expect(use5Signature.returnType != sema.types.errorType)
            }

            // 6: multiple distinct aliases
            do {
                let diags = diagnosticsForPath(paths[13], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)
                assertNoDiagnostic("KSWIFTK-SEMA-0023", in: diags)
            }

            // 7: alias + non-aliased import
            do {
                let diags = diagnosticsForPath(paths[15], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0002", in: diags)
            }
        }
    }

    // MARK: - Default import precedence

    @Test func testExplicitImportWinsOverDefaultImportForSameName() throws {
        let sources = [
            """
            package kotlin.io
            fun pick(x: Int) = "default"
            """,
            """
            package custom.io
            fun pick(x: Int) = 2
            """,
            """
            package app
            import custom.io.pick
            fun use() = pick(1)
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let useSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .function && ctx.interner.resolve(symbol.name) == "use"
        })?.id)
        let useSignature = try #require(sema.symbols.functionSignature(for: useSymbol))
        #expect(useSignature.returnType != sema.types.errorType)

        assertNoDiagnostic("KSWIFTK-SEMA-0003", in: ctx)
    }

}
#endif
