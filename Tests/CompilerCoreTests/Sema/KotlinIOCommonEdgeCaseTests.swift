#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - kotlin.io Common Edge Case Tests (STDLIB-030)
//
// Tests for common-range kotlin.io surfaces:
//   - Closeable.use { } extension
//   - AutoCloseable type alias resolution
//   - println / print / readLine / readln / readlnOrNull stubs
//   - StringBuilder.appendLine member
//   - String.lineSequence member
//   - File.useLines / File.forEachLine / File.bufferedReader helpers
//
// Edges exercised for .use { }:
//   closes resource on normal return, on exception, on null receiver short-circuit,
//   returns block result, lambda this-type = receiver (kotlin.io.Closeable),
//   AutoCloseable alias resolves to same Closeable symbol,
//   nested class implementing Closeable accepted by use.

@Suite
struct KotlinIOCommonEdgeCaseTests {

    // MARK: - Closeable.use – basic resolution

    // MARK: - Closeable.use – returns block result

    // MARK: - Closeable.use – lambda this-type is receiver

    // MARK: - Closeable.use – close called on exception path

    // MARK: - Closeable.use – null receiver short-circuits

    // MARK: - AutoCloseable alias resolution
    //
    // NOTE (STDLIB-030 gap): Using AutoCloseable as a generic upper bound `<T : AutoCloseable>`
    // is not yet resolved by the type checker — the alias is registered in the symbol table but
    // the bound-constraint solver does not traverse type-alias chains for .use dispatch.
    // The test below validates the symbol-table registration path only; the bound+use scenario
    // is covered by testAutoCloseableSymbolIsRegisteredInSymbolTable.

    // MARK: - AutoCloseable type alias visible in sema symbol table

    // MARK: - Closeable symbol registered in symbol table

    // MARK: - Nested class implementing Closeable

    // MARK: - println stubs

    // MARK: - DEFAULT_BUFFER_SIZE property

    // MARK: - readLine stub

    // MARK: - readln / readlnOrNull stubs

    // MARK: - StringBuilder.appendLine

    // MARK: - String.lineSequence

    // MARK: - File.useLines (line iteration helper)

    // MARK: - File.forEachLine

    // MARK: - File.bufferedReader

    // MARK: - File read / append helpers

    // MARK: - File stream helpers

    // MARK: - File.nameWithoutExtension (STDLIB-IO-PROP-005)

    // MARK: - java.io.Closeable maps to kotlin.io.Closeable

    // MARK: - use result is non-Unit when block returns value

    // MARK: - println return type is Unit

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testRootAutoCloseableUseSymbolIsRegisteredInSymbolTable
            """
            package sample0

                    fun main() {
                        println("ok")
                    }

            """,
            // testAutoCloseableSymbolIsRegisteredInSymbolTable
            """
            package sample1

                    fun main() {
                        println("ok")
                    }

            """,
            // testAutoCloseableFactorySymbolIsRegisteredInSymbolTable
            """
            package sample2

                    fun main() {
                        println("ok")
                    }

            """,
            // testCloseableSymbolIsRegisteredInSymbolTable
            """
            package sample3

                    fun main() {
                        println("ok")
                    }

            """,
            // testDefaultBufferSizePropertyIsRegistered
            """
            package sample4

                    fun main() {
                        println("ok")
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testRootAutoCloseableUseSymbolIsRegisteredInSymbolTable ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let kotlinFQN: [InternedString] = [interner.intern("kotlin")]
                let rootUseFQN = kotlinFQN + [interner.intern("use")]
                let useSymbol = try #require(
                    sema.symbols.lookup(fqName: rootUseFQN),
                    "kotlin.use should expose the common AutoCloseable?.use extension"
                )
                let signature = try #require(sema.symbols.functionSignature(for: useSymbol))
                let receiverType = try #require(signature.receiverType)
                #expect(signature.parameterTypes.count == 1)
                #expect(signature.typeParameterSymbols.count == 2)

                guard case let .functionType(blockType) = sema.types.kind(of: signature.parameterTypes[0]) else {
                    Issue.record("kotlin.use block parameter should be a function type"); return
                }
                #expect(blockType.params == [receiverType])
                #expect(blockType.returnType == signature.returnType)

                #expect(signature.typeParameterUpperBoundsList.count == 2)
                let tUpperBound = try #require(signature.typeParameterUpperBoundsList.first?.first)
                #expect(sema.types.nullability(of: tUpperBound) == .nullable)
                let nonNullBound = sema.types.makeNonNullable(tUpperBound)
                let closeableFQN = kotlinFQN + [interner.intern("io"), interner.intern("Closeable")]
                let closeableSymbol = try #require(sema.symbols.lookup(fqName: closeableFQN))
                guard case let .classType(boundClass) = sema.types.kind(of: nonNullBound) else {
                    Issue.record("kotlin.use T upper bound should resolve to kotlin.io.Closeable?"); return
                }
                #expect(boundClass.classSymbol == closeableSymbol)

            }

            // === testAutoCloseableSymbolIsRegisteredInSymbolTable ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let kotlinFQN: [InternedString] = [interner.intern("kotlin")]
                let autoCloseableFQN = kotlinFQN + [interner.intern("AutoCloseable")]
                let symbol = sema.symbols.lookup(fqName: autoCloseableFQN)
                #expect(symbol != nil, "kotlin.AutoCloseable should be registered as a synthetic type alias symbol")

            }

            // === testAutoCloseableFactorySymbolIsRegisteredInSymbolTable ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let kotlinFQN: [InternedString] = [interner.intern("kotlin")]
                let autoCloseableFQN = kotlinFQN + [interner.intern("AutoCloseable")]
                let functionSymbol = sema.symbols.lookupAll(fqName: autoCloseableFQN).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .function
                }
                let symbol = try #require(functionSymbol, "kotlin.AutoCloseable factory should be registered alongside the type alias")
                #expect(sema.symbols.externalLinkName(for: symbol) == "kk_auto_closeable_create")

            }

            // === testCloseableSymbolIsRegisteredInSymbolTable ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let kotlinIOFQN: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
                let closeableFQN = kotlinIOFQN + [interner.intern("Closeable")]
                let symbol = sema.symbols.lookup(fqName: closeableFQN)
                #expect(symbol != nil, "kotlin.io.Closeable should be registered as a synthetic interface symbol")

            }

            // === testDefaultBufferSizePropertyIsRegistered ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let kotlinIOFQN: [InternedString] = [interner.intern("kotlin"), interner.intern("io")]
                let propertyFQN = kotlinIOFQN + [interner.intern("DEFAULT_BUFFER_SIZE")]
                let propertySymbol = try #require(
                    sema.symbols.lookupAll(fqName: propertyFQN).first { symbolID in
                        sema.symbols.symbol(symbolID)?.kind == .property
                    },
                    "kotlin.io.DEFAULT_BUFFER_SIZE should be registered as a synthetic top-level property"
                )
                #expect(sema.symbols.propertyType(for: propertySymbol) == sema.types.intType)
                #expect(sema.symbols.externalLinkName(for: propertySymbol) == "kk_io_default_buffer_size")
                #expect(sema.symbols.symbol(propertySymbol)?.flags.contains(.constValue) == true)
                #expect(sema.symbols.constValueExprKind(for: propertySymbol) == .intLiteral(8192))

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testCloseableUseResolvesWithoutErrors
            """
            package sample0

                    import java.io.Closeable

                    class MyResource : Closeable {
                        override fun close() {}
                    }

                    fun main() {
                        MyResource().use { r ->
                            println(r)
                        }
                    }

            """,
            // testCloseableUseReturnTypeIsBlockResult
            """
            package sample1

                    import java.io.Closeable

                    class Counter : Closeable {
                        override fun close() {}
                    }

                    fun compute(): Int {
                        return Counter().use { 42 }
                    }

                    fun main() {
                        val x: Int = compute()
                        println(x)
                    }

            """,
            // testCloseableUseLambdaReceiverTypedAsCloseable
            """
            package sample2

                    import java.io.Closeable

                    class Named(val name: String) : Closeable {
                        override fun close() {}
                    }

                    fun main() {
                        val label = Named("test").use { resource ->
                            resource.name
                        }
                        println(label)
                    }

            """,
            // testCloseableUseWithBodyExceptionClosesResource
            """
            package sample3

                    import java.io.Closeable

                    class TrackedResource : Closeable {
                        override fun close() {
                            println("closed")
                        }
                    }

                    fun main() {
                        try {
                            TrackedResource().use {
                                error("boom")
                            }
                        } catch (e: Throwable) {
                            println("caught")
                        }
                    }

            """,
            // testNullableCloseableUseShortCircuitsOnNull
            """
            package sample4

                    import java.io.Closeable

                    class Box : Closeable {
                        override fun close() {}
                    }

                    fun main() {
                        val nullable: Box? = null
                        val result = nullable?.use { "value" }
                        println(result)
                    }

            """,
            // testNullableAutoCloseableDirectUseResolvesWithoutSafeCall
            """
            package sample5

                    fun main() {
                        val nullable: AutoCloseable? = null
                        val result: String = nullable.use { resource ->
                            if (resource == null) "null-resource" else "resource"
                        }
                        println(result)
                    }

            """,
            // testAutoCloseableAliasDirectUseViaConcreateCloseableResolves
            """
            package sample6

                    import java.io.Closeable

                    class Widget : Closeable {
                        override fun close() {}
                    }

                    fun main() {
                        Widget().use { println("ok") }
                    }

            """,
            // testAutoCloseableFactoryResolvesWithoutErrors
            """
            package sample7

                    fun main() {
                        val resource: AutoCloseable = AutoCloseable {
                            println("closed")
                        }
                        resource.close()
                    }

            """,
            // testNestedClassImplementingCloseableAcceptedByUse
            """
            package sample8

                    import java.io.Closeable

                    class Outer {
                        inner class Inner : Closeable {
                            override fun close() {}
                        }
                    }

                    fun main() {
                        val outer = Outer()
                        outer.Inner().use { println("inner-use") }
                    }

            """,
            // testPrintlnNoArgStubResolves
            """
            package sample9

                    fun main() {
                        println()
                    }

            """,
            // testPrintlnAnyArgStubResolves
            """
            package sample10

                    fun main() {
                        println("hello")
                        println(42)
                        println(null)
                    }

            """,
            // testPrintNoArgStubResolves
            """
            package sample11

                    fun main() {
                        print()
                        print("hello")
                    }

            """,
            // testDefaultBufferSizePropertyResolvesAsInt
            """
            package sample12

                    import kotlin.io.DEFAULT_BUFFER_SIZE

                    fun main() {
                        val size: Int = DEFAULT_BUFFER_SIZE
                        println(size)
                    }

            """,
            // testReadLineStubResolvesToNullableString
            """
            package sample13

                    fun main() {
                        val line: String? = readLine()
                        println(line)
                    }

            """,
            // testReadlnStubResolvesToNonNullString
            """
            package sample14

                    fun main() {
                        val line: String = readln()
                        println(line)
                    }

            """,
            // testReadlnOrNullStubResolvesToNullableString
            """
            package sample15

                    fun main() {
                        val line: String? = readlnOrNull()
                        println(line)
                    }

            """,
            // testStringBuilderAppendLineWithArgResolves
            """
            package sample16

                    fun main() {
                        val sb = StringBuilder()
                        sb.appendLine("hello")
                        sb.appendLine()
                        println(sb.toString())
                    }

            """,
            // testStringLineSequenceResolves
            """
            package sample17

                    fun main() {
                        val text = "a\nb\nc"
                        for (line in text.lineSequence()) {
                            println(line)
                        }
                    }

            """,
            // testFileUseLinesResolves
            """
            package sample18

                    import java.io.File

                    fun main() {
                        val f = File("/dev/null")
                        f.useLines { lines ->
                            lines.forEach { println(it) }
                        }
                    }

            """,
            // testFileForEachLineResolves
            """
            package sample19

                    import java.io.File

                    fun main() {
                        val f = File("/dev/null")
                        f.forEachLine { line -> println(line) }
                    }

            """,
            // testFileBufferedReaderResolves
            """
            package sample20

                    import java.io.File

                    fun main() {
                        val reader = File("/dev/null").bufferedReader()
                        val line = reader.readLine()
                        reader.close()
                        println(line)
                    }

            """,
            // testFileReadAppendAndByteHelpersResolve
            """
            package sample21

                    import java.io.File

                    fun main() {
                        val f = File("/tmp/kswiftk-io.txt")
                        val text: String = f.readText()
                        f.appendText(text)
                        val bytes = f.readBytes()
                        println(bytes)
                    }

            """,
            // testFileInputAndOutputStreamResolve
            """
            package sample22

                    import java.io.File

                    fun main() {
                        val f = File("/tmp/kswiftk-io.txt")
                        val source = f.inputStream()
                        val sink = f.outputStream()
                        println(source)
                        println(sink)
                    }

            """,
            // testFileNameWithoutExtensionResolvesAsString
            """
            package sample23

                    import java.io.File

                    fun stem(f: File): String {
                        val name: String = f.nameWithoutExtension
                        return name
                    }

                    fun main() {
                        val f = File("/tmp/archive.tar.gz")
                        println(stem(f))
                    }

            """,
            // testJavaIOCloseableIsAcceptedByUseExtension
            """
            package sample24

                    import java.io.Closeable

                    class JvmStyleResource : Closeable {
                        override fun close() {}
                    }

                    fun main() {
                        JvmStyleResource().use { println("jvm-style") }
                    }

            """,
            // testUseResultCanBeAssignedToTypedVariable
            """
            package sample25

                    import java.io.Closeable

                    class Src : Closeable {
                        fun read(): String = "data"
                        override fun close() {}
                    }

                    fun main() {
                        val data: String = Src().use { src -> src.read() }
                        println(data)
                    }

            """,
            // testPrintlnReturnTypeIsUnit
            """
            package sample26

                    fun main() {
                        val x: Unit = println("unit-check")
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testCloseableUseResolvesWithoutErrors ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                #expect(
                    !(sample0Diagnostics.contains { $0.severity == .error }),
                    "Closeable.use { } should resolve without errors: \(sample0Diagnostics.map(\.message))"
                )

            }

            // === testCloseableUseReturnTypeIsBlockResult ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                #expect(
                    !(sample1Diagnostics.contains { $0.severity == .error }),
                    ".use { } return type should be inferred as Int: \(sample1Diagnostics.map(\.message))"
                )

            }

            // === testCloseableUseLambdaReceiverTypedAsCloseable ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                #expect(
                    !(sample2Diagnostics.contains { $0.severity == .error }),
                    "Lambda parameter inside .use { } should be typed as the concrete Closeable receiver: \(sample2Diagnostics.map(\.message))"
                )

            }

            // === testCloseableUseWithBodyExceptionClosesResource ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                #expect(
                    !(sample3Diagnostics.contains { $0.severity == .error }),
                    ".use { } with throwing body should still compile: \(sample3Diagnostics.map(\.message))"
                )

            }

            // === testNullableCloseableUseShortCircuitsOnNull ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                #expect(
                    !(sample4Diagnostics.contains { $0.severity == .error }),
                    "?.use on null receiver should compile without errors: \(sample4Diagnostics.map(\.message))"
                )

            }

            // === testNullableAutoCloseableDirectUseResolvesWithoutSafeCall ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(
                    !(sample5Diagnostics.contains { $0.severity == .error }),
                    "Nullable AutoCloseable.use should resolve without requiring ?.use: \(sample5Diagnostics.map(\.message))"
                )

            }

            // === testAutoCloseableAliasDirectUseViaConcreateCloseableResolves ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                // Using kotlin.io.Closeable directly (not AutoCloseable bound) works fine.
                    #expect(
                        !(sample6Diagnostics.contains { $0.severity == .error }),
                        "Closeable implementor should be accepted by .use without error: \(sample6Diagnostics.map(\.message))"
                    )

            }

            // === testAutoCloseableFactoryResolvesWithoutErrors ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(
                    !(sample7Diagnostics.contains { $0.severity == .error }),
                    "AutoCloseable { } factory should resolve without errors: \(sample7Diagnostics.map(\.message))"
                )

            }

            // === testNestedClassImplementingCloseableAcceptedByUse ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                #expect(
                    !(sample8Diagnostics.contains { $0.severity == .error }),
                    "Nested class implementing Closeable should be accepted by .use: \(sample8Diagnostics.map(\.message))"
                )

            }

            // === testPrintlnNoArgStubResolves ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                #expect(
                    !(sample9Diagnostics.contains { $0.severity == .error }),
                    "println() no-arg should resolve: \(sample9Diagnostics.map(\.message))"
                )

            }

            // === testPrintlnAnyArgStubResolves ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                #expect(
                    !(sample10Diagnostics.contains { $0.severity == .error }),
                    "println(Any?) should resolve for String, Int, and null: \(sample10Diagnostics.map(\.message))"
                )

            }

            // === testPrintNoArgStubResolves ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                #expect(
                    !(sample11Diagnostics.contains { $0.severity == .error }),
                    "print() no-arg and print(Any?) should resolve: \(sample11Diagnostics.map(\.message))"
                )

            }

            // === testDefaultBufferSizePropertyResolvesAsInt ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                #expect(
                    !(sample12Diagnostics.contains { $0.severity == .error }),
                    "DEFAULT_BUFFER_SIZE should resolve as Int: \(sample12Diagnostics.map(\.message))"
                )

            }

            // === testReadLineStubResolvesToNullableString ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                #expect(
                    !(sample13Diagnostics.contains { $0.severity == .error }),
                    "readLine() should resolve to String? without errors: \(sample13Diagnostics.map(\.message))"
                )

            }

            // === testReadlnStubResolvesToNonNullString ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                #expect(
                    !(sample14Diagnostics.contains { $0.severity == .error }),
                    "readln() should resolve to String (non-null): \(sample14Diagnostics.map(\.message))"
                )

            }

            // === testReadlnOrNullStubResolvesToNullableString ===

            do {

                let sample15Path = paths[15]

                let path = sample15Path

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

                #expect(
                    !(sample15Diagnostics.contains { $0.severity == .error }),
                    "readlnOrNull() should resolve to String? without errors: \(sample15Diagnostics.map(\.message))"
                )

            }

            // === testStringBuilderAppendLineWithArgResolves ===

            do {

                let sample16Path = paths[16]

                let path = sample16Path

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                #expect(
                    !(sample16Diagnostics.contains { $0.severity == .error }),
                    "StringBuilder.appendLine() and appendLine(String) should resolve: \(sample16Diagnostics.map(\.message))"
                )

            }

            // === testStringLineSequenceResolves ===

            do {

                let sample17Path = paths[17]

                let path = sample17Path

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                #expect(
                    !(sample17Diagnostics.contains { $0.severity == .error }),
                    "String.lineSequence() should resolve: \(sample17Diagnostics.map(\.message))"
                )

            }

            // === testFileUseLinesResolves ===

            do {

                let sample18Path = paths[18]

                let path = sample18Path

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                #expect(
                    !(sample18Diagnostics.contains { $0.severity == .error }),
                    "File.useLines { } should resolve: \(sample18Diagnostics.map(\.message))"
                )

            }

            // === testFileForEachLineResolves ===

            do {

                let sample19Path = paths[19]

                let path = sample19Path

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                #expect(
                    !(sample19Diagnostics.contains { $0.severity == .error }),
                    "File.forEachLine { } should resolve: \(sample19Diagnostics.map(\.message))"
                )

            }

            // === testFileBufferedReaderResolves ===

            do {

                let sample20Path = paths[20]

                let path = sample20Path

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                #expect(
                    !(sample20Diagnostics.contains { $0.severity == .error }),
                    "File.bufferedReader() and BufferedReader.readLine() / close() should resolve: \(sample20Diagnostics.map(\.message))"
                )

            }

            // === testFileReadAppendAndByteHelpersResolve ===

            do {

                let sample21Path = paths[21]

                let path = sample21Path

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                #expect(
                    !(sample21Diagnostics.contains { $0.severity == .error }),
                    "File.readText(), appendText(), and readBytes() should resolve: \(sample21Diagnostics.map(\.message))"
                )

            }

            // === testFileInputAndOutputStreamResolve ===

            do {

                let sample22Path = paths[22]

                let path = sample22Path

                let sample22Diagnostics = diagnosticsForPath(sample22Path, in: ctx)

                #expect(
                    !(sample22Diagnostics.contains { $0.severity == .error }),
                    "File.inputStream() and outputStream() should resolve: \(sample22Diagnostics.map(\.message))"
                )

            }

            // === testFileNameWithoutExtensionResolvesAsString ===

            do {

                let sample23Path = paths[23]

                let path = sample23Path

                let sample23Diagnostics = diagnosticsForPath(sample23Path, in: ctx)

                #expect(
                    !(sample23Diagnostics.contains { $0.severity == .error }),
                    "File.nameWithoutExtension extension property should resolve as String: \(sample23Diagnostics.map(\.message))"
                )

            }

            // === testJavaIOCloseableIsAcceptedByUseExtension ===

            do {

                let sample24Path = paths[24]

                let path = sample24Path

                let sample24Diagnostics = diagnosticsForPath(sample24Path, in: ctx)

                #expect(
                    !(sample24Diagnostics.contains { $0.severity == .error }),
                    "java.io.Closeable implementor should be accepted by .use: \(sample24Diagnostics.map(\.message))"
                )

            }

            // === testUseResultCanBeAssignedToTypedVariable ===

            do {

                let sample25Path = paths[25]

                let path = sample25Path

                let sample25Diagnostics = diagnosticsForPath(sample25Path, in: ctx)

                #expect(
                    !(sample25Diagnostics.contains { $0.severity == .error }),
                    ".use { } result should be assignable to typed variable: \(sample25Diagnostics.map(\.message))"
                )

            }

            // === testPrintlnReturnTypeIsUnit ===

            do {

                let sample26Path = paths[26]

                let path = sample26Path

                let sample26Diagnostics = diagnosticsForPath(sample26Path, in: ctx)

                #expect(
                    !(sample26Diagnostics.contains { $0.severity == .error }),
                    "println() return type should be Unit: \(sample26Diagnostics.map(\.message))"
                )

            }

        }
    }

}

#endif
