#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension CompilerCoreTests {

    @Test func testImportsAndExtensionResolutionSema() throws {
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

            """
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

        }
    }


    @Test func testBuildASTParsesExtensionFunctionReceiverType() throws {
        let source = """
        fun String.echo(): String = this
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let firstFile = try #require(ast.files.first)
        let firstDeclID = try #require(firstFile.topLevelDecls.first)
        let decl = try #require(ast.arena.decl(firstDeclID))
        guard case let .funDecl(funDecl) = decl else {
            Issue.record("Expected function declaration")
            return
        }

        #expect(funDecl.name != .invalid)
        let receiverTypeID = try #require(funDecl.receiverType)
        let receiverType = try #require(ast.arena.typeRef(receiverTypeID))
        if case let .named(path, _, nullable) = receiverType {
            #expect(!(nullable))
            #expect(path.count == 1)
            #expect(ctx.interner.resolve(path[0]) == "String")
        } else {
            Issue.record("Expected named receiver type")
        }
    }


    @Test func testBuildASTParsesNullableExtensionFunctionReceiverType() throws {
        let source = """
        fun String?.echoNullable(): String = this ?: ""
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let firstFile = try #require(ast.files.first)
        let firstDeclID = try #require(firstFile.topLevelDecls.first)
        let decl = try #require(ast.arena.decl(firstDeclID))
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


    @Test func testBuildASTParsesClassTypeParameterVariance() throws {
        let source = """
        class Box<out T, in U, V>
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try #require(ctx.ast)
        let firstFile = try #require(ast.files.first)
        let firstDeclID = try #require(firstFile.topLevelDecls.first)
        let decl = try #require(ast.arena.decl(firstDeclID))
        guard case let .classDecl(classDecl) = decl else {
            Issue.record("Expected class declaration")
            return
        }

        #expect(classDecl.typeParams.count == 3)
        #expect(classDecl.typeParams.map(\.variance) == [.out, .in, .invariant])
        #expect(classDecl.typeParams.map { ctx.interner.resolve($0.name) } == ["T", "U", "V"])
    }


    @Test func testSemaResolvesTopLevelFunctionAcrossFilesInSamePackage() throws {
        let sources = [
            """
            package demo
            fun helper(x: Int) = x
            """,
            """
            package demo
            fun use() = helper(1)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }


    @Test func testSemaResolvesExplicitImportAcrossPackages() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper
            fun use() = helper(1)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }


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


    @Test func testImportAliasWildcardDiagnostic() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib as L
            fun use() = 1
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0022", in: ctx)
    }


    @Test func testImportAliasDuplicateDiagnostic() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x
            """,
            """
            package app
            import lib.foo as X
            import lib.bar as X
            fun use() = 1
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }


    @Test func testImportAliasResolvesAcrossPackages() throws {
        let sources = [
            """
            package lib
            fun helper(x: Int) = x
            """,
            """
            package app
            import lib.helper as h
            fun use() = h(1)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }


    @Test func testImportAliasReturnTypeIsInferred() throws {
        let sources = [
            """
            package lib
            fun compute(x: Int): Int = x + 1
            """,
            """
            package app
            import lib.compute as calc
            fun use(): Int = calc(5)
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
        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }


    @Test func testImportAliasMultipleDistinctAliasesInSameFile() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x + 1
            """,
            """
            package app
            import lib.foo as f
            import lib.bar as b
            fun use() = f(1) + b(2)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
    }


    @Test func testImportAliasCoexistsWithNonAliasedImport() throws {
        let sources = [
            """
            package lib
            fun foo(x: Int) = x
            fun bar(x: Int) = x + 1
            """,
            """
            package app
            import lib.foo as f
            import lib.bar
            fun use() = f(1) + bar(2)
            """,
        ]
        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
    }

}
#endif
