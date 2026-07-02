@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SemanticsAndUtilitiesRegressionTests {
    private func memberCallExprIDs(named name: String, in ast: ASTModule, interner: StringInterner) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == name
            else {
                return nil
            }
            return exprID
        }
    }

    @Test
    func testAtomicStoreExpressionIsTypedAsUnit() throws {
        let source = """
        import kotlin.concurrent.atomics.AtomicInt

        fun main() {
            val ai = AtomicInt(1)
            val x = ai.store(2)
            val y: Unit = x
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "Atomic.store() should be typed as Unit: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions() throws {
        let source = """
        class Config(
            val host: String,
            val port: Int,
            val debug: Boolean
        ) {
            class Builder {
                var host: String = "localhost"
                var port: Int = 8080
                var debug: Boolean = false

                fun host(h: String): Builder { host = h; return this }
                fun port(p: Int): Builder { port = p; return this }
                fun debug(d: Boolean): Builder { debug = d; return this }
                fun build(): Config = Config(host, port, debug)
            }
        }

        fun main() {
            val cfg = Config.Builder()
                .host("example.com")
                .port(443)
                .debug(true)
                .build()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let helpers = TypeCheckHelpers()

            let builderSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("Config"), interner.intern("Builder")]))
            let builderType = sema.types.make(.classType(ClassType(classSymbol: builderSymbol, args: [], nullability: .nonNull)))
            let portCandidates = helpers.collectMemberFunctionCandidates(
                named: interner.intern("port"),
                receiverType: builderType,
                sema: sema,
                interner: interner
            )
            #expect(portCandidates.contains { candidate in
                    sema.symbols.symbol(candidate)?.fqName == [interner.intern("Config"), interner.intern("Builder"), interner.intern("port")]
                }, "Expected Config.Builder.port to be visible among candidates")

            let hostCall = try #require(memberCallExprIDs(named: "host", in: ast, interner: interner).first)
            let portCall = try #require(memberCallExprIDs(named: "port", in: ast, interner: interner).first)
            let hostExprType = sema.bindings.exprTypes[hostCall]
            let portExprType = sema.bindings.exprTypes[portCall]

            if case let .memberCall(portReceiverExpr, _, _, _, _) = ast.arena.expr(portCall) {
                let portReceiverType = sema.bindings.exprTypes[portReceiverExpr]
                #expect(portReceiverType == builderType, "Expected host() result used as port() receiver to stay Config.Builder, got \(portReceiverType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
            } else {
                Issue.record("Expected port call expression to be a memberCall")
            }

            #expect(sema.bindings.callBinding(for: hostCall)?.chosenCallee != nil, "Expected host() call to resolve")
            #expect(hostExprType == builderType, "Expected host() to return Config.Builder, got \(hostExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
            #expect(portExprType == builderType, "Expected port() to return Config.Builder, got \(portExprType.map(sema.types.renderType) ?? "nil"); diagnostics: \(diagnostics)")
            #expect(sema.bindings.callBinding(for: portCall)?.chosenCallee != nil, "Expected port() call to resolve; diagnostics: \(diagnostics)")
        }
    }

    @Test
    func testLegacyAtomicTypeAliasStillResolves() throws {
        let source = """
        import kotlin.concurrent.AtomicInt

        fun main() {
            val ai = AtomicInt(1)
            println(ai.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "Legacy kotlin.concurrent.AtomicInt alias should still resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testExperimentalAtomicOptInMarkerIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.ExperimentalAtomicApi

        fun main() {
            println("ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAtomicReferenceInAtomicsPackageIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.ExperimentalAtomicApi
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val ar = AtomicReference("hello")
            println(ar.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAtomicLongInConcurrentPackageIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.AtomicLong

        fun main() {
            val al = AtomicLong(42L)
            println(al.load())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "AtomicLong in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAtomicIntArrayInConcurrentPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.AtomicIntArray

        fun main() {
            val values = AtomicIntArray(2)
            values.storeAt(0, 10)
            val ok = values.compareAndSetAt(0, 10, 11)
            println(if (ok) values.loadAt(0) else values.size)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "AtomicIntArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAtomicLongArrayInConcurrentPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.AtomicLongArray

        fun main() {
            val values = AtomicLongArray(2)
            values.storeAt(0, 10L)
            val ok = values.compareAndSetAt(0, 10L, 11L)
            println(if (ok) values.loadAt(0) else values.size.toLong())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "AtomicLongArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testExperimentalAtomicArraysInAtomicsPackageAreResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicIntArray
        import kotlin.concurrent.atomics.AtomicLongArray

        fun main() {
            val ints = AtomicIntArray(2)
            ints.storeAt(0, 10)
            ints.storeAt(1, 20)
            val ok = ints.compareAndSetAt(1, 20, 21)
            val old = ints.exchangeAt(0, 11)
            val sum = ints.loadAt(0) + ints.loadAt(1) + if (ok) old else 0

            val longs = AtomicLongArray(1)
            longs.storeAt(0, 1L)
            println(sum)
            println(longs.addAndFetchAt(0, 1L))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "Experimental atomic arrays in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testCopyActionContextInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.CopyActionContext

        class CopyContextHolder(val context: CopyActionContext?)

        fun keepCopyContext(context: CopyActionContext): CopyActionContext {
            return context
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "CopyActionContext in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testAtomicNativePtrInAtomicsPackageSurfaceIsResolved() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicNativePtr
        import kotlinx.cinterop.NativePtr

        fun touchAtomicNativePtr(initial: NativePtr, next: NativePtr): NativePtr {
            val atomic = AtomicNativePtr(initial)
            atomic.value = next
            atomic.store(initial)
            val loaded = atomic.load()
            val exchanged = atomic.exchange(next)
            val previous = atomic.getAndSet(loaded)
            atomic.compareAndSet(exchanged, loaded)
            val fetched = atomic.fetchAndUpdate { current -> current }
            return atomic.compareAndExchange(fetched, previous)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "AtomicNativePtr in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathNameExtensionPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.name

        fun pathName(path: Path): String {
            val name: String = path.name
            return name
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.name extension property in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathNameWithoutExtensionPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.nameWithoutExtension

        fun pathStem(path: Path): String {
            val name: String = path.nameWithoutExtension
            return name
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.nameWithoutExtension extension property in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathExtensionPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.extension

        fun pathExtension(path: Path): String {
            val ext: String = path.extension
            return ext
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.extension extension property in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathStringExtensionPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.pathString

        fun rawPath(path: Path): String {
            val value: String = path.pathString
            return value
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.pathString extension property in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testCopyActionResultInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.CopyActionResult

        fun nextCopyActionResult(result: CopyActionResult): CopyActionResult {
            return when (result) {
                CopyActionResult.CONTINUE -> CopyActionResult.SKIP_SUBTREE
                CopyActionResult.SKIP_SUBTREE -> CopyActionResult.TERMINATE
                CopyActionResult.TERMINATE -> CopyActionResult.CONTINUE
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "CopyActionResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathAppendTextExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendText
        import kotlin.text.Charsets

        fun appendPathText(path: Path, text: CharSequence): Path {
            val first = path.appendText(text)
            val second = path.appendText(text, Charsets.UTF_8)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.appendText extension functions in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let appendTextSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "appendText"].map(interner.intern))
            let defaultAppendText = try #require(appendTextSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charSequenceType]
                    && signature.returnType == pathType
            })
            let charsetAppendText = try #require(appendTextSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charSequenceType, charsetType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: defaultAppendText) == "kk_path_appendText_default")
            #expect(symbols.externalLinkName(for: charsetAppendText) == "kk_path_appendText")

            let defaultSignature = try #require(symbols.functionSignature(for: defaultAppendText))
            let charsetSignature = try #require(symbols.functionSignature(for: charsetAppendText))
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(charsetSignature.valueParameterHasDefaultValues == [false, false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "appendText", in: ast, interner: interner)

            #expect(callExprs.count == 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.contains(defaultAppendText))
            #expect(chosenCallees.contains(charsetAppendText))
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == pathType)
            }
        }
    }

    @Test
    func testPathWriteTextOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writeText
        import kotlin.text.Charsets

        fun writePathText(path: Path, text: CharSequence, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.writeText(text, charset, options) extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let writeTextSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writeText"].map(interner.intern))
            let writeText = try #require(writeTextSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charSequenceType, charsetType, openOptionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: writeText) == "kk_path_writeText_options")

            let signature = try #require(symbols.functionSignature(for: writeText))
            #expect(signature.valueParameterHasDefaultValues == [false, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathCopyToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.CopyOption
        import kotlin.io.path.Path
        import kotlin.io.path.copyTo

        fun copyPath(source: Path, target: Path, option: CopyOption): Path {
            val first = source.copyTo(target)
            val second = source.copyTo(target, option)
            val third = source.copyTo(target, true)
            return third
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.copyTo(target, options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let copyOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "CopyOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let copyOptionType = types.make(.classType(ClassType(classSymbol: copyOptionSymbol, args: [], nullability: .nonNull)))
            let copyToSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "copyTo"].map(interner.intern))
            let copyTo = try #require(copyToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, copyOptionType]
                    && signature.returnType == pathType
            })
            let overwriteCopyTo = try #require(copyToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, types.booleanType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: copyTo) == "kk_path_copyTo_options")
            #expect(symbols.externalLinkName(for: overwriteCopyTo) == "kk_path_copyTo_overwrite")

            let signature = try #require(symbols.functionSignature(for: copyTo))
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(signature.valueParameterIsVararg == [false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "copyTo", in: ast, interner: interner)
            #expect(callExprs.count == 3)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.filter { $0 == copyTo }.count == 2)
            #expect(chosenCallees.filter { $0 == overwriteCopyTo }.count == 1)
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == pathType)
            }
        }
    }

    @Test
    func testPathFileAttributesViewOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.FileAttributeView
        import kotlin.io.path.Path
        import kotlin.io.path.fileAttributesView

        fun <V : FileAttributeView> attributesView(path: Path, option: LinkOption): V {
            val first: V = path.fileAttributesView<V>()
            val second: V = path.fileAttributesView<V>(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.fileAttributesView<V>(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let fileAttributeViewSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttributeView"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let fileAttributeViewType = types.make(.classType(ClassType(classSymbol: fileAttributeViewSymbol, args: [], nullability: .nonNull)))
            let fileAttributesViewSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileAttributesView"].map(interner.intern))
            let fileAttributesView = try #require(fileAttributesViewSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == returnType
            })
            #expect(symbols.externalLinkName(for: fileAttributesView) == "kk_path_fileAttributesView")

            let signature = try #require(symbols.functionSignature(for: fileAttributesView))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.typeParameterUpperBoundsList == [[fileAttributeViewType]])
            #expect(symbols.typeParameterUpperBounds(for: try #require(signature.typeParameterSymbols.first)) == [fileAttributeViewType])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "fileAttributesView", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == fileAttributesView)
                #expect(sema.bindings.exprTypes[callExpr] != nil)
            }
        }
    }

    @Test
    func testPathGetLastModifiedTimeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.FileTime
        import kotlin.io.path.Path
        import kotlin.io.path.getLastModifiedTime

        fun modifiedTime(path: Path, option: LinkOption): FileTime {
            val first = path.getLastModifiedTime()
            val second = path.getLastModifiedTime(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.getLastModifiedTime(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let fileTimeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileTime"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let fileTimeType = types.make(.classType(ClassType(classSymbol: fileTimeSymbol, args: [], nullability: .nonNull)))
            let getLastModifiedTimeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getLastModifiedTime"].map(interner.intern))
            let getLastModifiedTime = try #require(getLastModifiedTimeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == fileTimeType
            })
            #expect(symbols.externalLinkName(for: getLastModifiedTime) == "kk_path_getLastModifiedTime")

            let signature = try #require(symbols.functionSignature(for: getLastModifiedTime))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getLastModifiedTime", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == getLastModifiedTime)
                #expect(sema.bindings.exprTypes[callExpr] == fileTimeType)
            }
        }
    }

    @Test
    func testPathIsDirectoryOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.isDirectory

        fun directoryPath(path: Path, option: LinkOption): Boolean {
            val first = path.isDirectory()
            val second = path.isDirectory(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.isDirectory(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let isDirectorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "isDirectory"].map(interner.intern))
            let isDirectory = try #require(isDirectorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            #expect(symbols.externalLinkName(for: isDirectory) == "kk_path_isDirectory")

            let signature = try #require(symbols.functionSignature(for: isDirectory))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "isDirectory", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == isDirectory)
                #expect(sema.bindings.exprTypes[callExpr] == types.booleanType)
            }
        }
    }

    @Test
    func testPathListDirectoryEntriesGlobExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.collections.List
        import kotlin.io.path.Path
        import kotlin.io.path.listDirectoryEntries

        fun entries(path: Path): List<Path> {
            val first = path.listDirectoryEntries()
            val second = path.listDirectoryEntries("*.kt")
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.listDirectoryEntries(glob) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let listSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "List"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let listOfPathType = types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
            let listDirectoryEntriesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "listDirectoryEntries"].map(interner.intern))
            let listDirectoryEntries = try #require(listDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType]
                    && signature.returnType == listOfPathType
            })
            #expect(symbols.externalLinkName(for: listDirectoryEntries) == "kk_path_listDirectoryEntries")

            let signature = try #require(symbols.functionSignature(for: listDirectoryEntries))
            #expect(signature.valueParameterHasDefaultValues == [true])
            #expect(signature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "listDirectoryEntries", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == listDirectoryEntries)
                #expect(sema.bindings.exprTypes[callExpr] == listOfPathType)
            }
        }
    }

    @Test
    func testPathOutputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.io.OutputStream
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.outputStream

        fun openSink(path: Path, option: OpenOption): OutputStream {
            val first = path.outputStream()
            val second = path.outputStream(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.outputStream(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let outputStreamSymbol = try #require(symbols.lookup(fqName: ["java", "io", "OutputStream"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let outputStreamType = types.make(.classType(ClassType(classSymbol: outputStreamSymbol, args: [], nullability: .nonNull)))
            let outputStreamSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "outputStream"].map(interner.intern))
            let outputStream = try #require(outputStreamSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [openOptionType]
                    && signature.returnType == outputStreamType
            })
            #expect(symbols.externalLinkName(for: outputStream) == "kk_path_outputStream")

            let signature = try #require(symbols.functionSignature(for: outputStream))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "outputStream", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == outputStream)
                #expect(sema.bindings.exprTypes[callExpr] == outputStreamType)
            }
        }
    }

    @Test
    func testPathInputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.io.InputStream
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.inputStream

        fun openSource(path: Path, option: OpenOption): InputStream {
            val first = path.inputStream()
            val second = path.inputStream(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.inputStream(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let inputStreamSymbol = try #require(symbols.lookup(fqName: ["java", "io", "InputStream"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let inputStreamType = types.make(.classType(ClassType(classSymbol: inputStreamSymbol, args: [], nullability: .nonNull)))
            let inputStreamSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "inputStream"].map(interner.intern))
            let inputStream = try #require(inputStreamSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [openOptionType]
                    && signature.returnType == inputStreamType
            })
            #expect(symbols.externalLinkName(for: inputStream) == "kk_path_inputStream")

            let signature = try #require(symbols.functionSignature(for: inputStream))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "inputStream", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == inputStream)
                #expect(sema.bindings.exprTypes[callExpr] == inputStreamType)
            }
        }
    }

    @Test
    func testPathBaseSubpathsTopLevelFactoryInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path

        fun makePath(): Path {
            return Path("src", "main", "App.kt")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path(base, subpaths) top-level factory in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let pathFactorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            let pathFactory = try #require(pathFactorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [types.stringType, types.stringType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: pathFactory) == "kk_path_get_base_subpaths")

            let signature = try #require(symbols.functionSignature(for: pathFactory))
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(signature.valueParameterIsVararg == [false, true])
            #expect(signature.valueParameterSymbols.count == 2)
            #expect(interner.resolve(try #require(symbols.symbol(signature.valueParameterSymbols[0])?.name)) == "base")
            #expect(interner.resolve(try #require(symbols.symbol(signature.valueParameterSymbols[1])?.name)) == "subpaths")

            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return interner.resolve(calleeName) == "Path"
            })
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == pathFactory)
            #expect(sema.bindings.exprTypes[callExpr] == pathType)
        }
    }

    @Test
    func testPathFileVisitorBuilderActionTopLevelFunctionSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.FileVisitor
        import kotlin.io.path.Path
        import kotlin.io.path.fileVisitor

        fun visitor(): FileVisitor<Path> {
            return fileVisitor {
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "fileVisitor(builderAction) top-level function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileVisitorSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "FileVisitor"].map(interner.intern)))
            let fileVisitorBuilderSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "FileVisitorBuilder"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileVisitorOfPathType = types.make(.classType(ClassType(
                classSymbol: fileVisitorSymbol,
                args: [.invariant(pathType)],
                nullability: .nonNull
            )))
            let fileVisitorBuilderType = types.make(.classType(ClassType(
                classSymbol: fileVisitorBuilderSymbol,
                args: [],
                nullability: .nonNull
            )))
            let builderActionType = types.make(.functionType(FunctionType(
                receiver: fileVisitorBuilderType,
                params: [],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let fileVisitorSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileVisitor"].map(interner.intern))
            let fileVisitor = try #require(fileVisitorSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.parameterTypes == [builderActionType]
                    && signature.returnType == fileVisitorOfPathType
            })
            #expect(symbols.externalLinkName(for: fileVisitor) == "kk_path_fileVisitor")

            let signature = try #require(symbols.functionSignature(for: fileVisitor))
            #expect(signature.receiverType == nil)
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])
            #expect(types.nominalTypeParameterSymbols(for: fileVisitorSymbol).count == 1)

            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return interner.resolve(calleeName) == "fileVisitor"
            })
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == fileVisitor)
            #expect(sema.bindings.exprTypes[callExpr] == fileVisitorOfPathType)
        }
    }

    @Test
    func testPathVisitFileTreeVisitorExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.FileVisitor
        import kotlin.io.path.Path
        import kotlin.io.path.visitFileTree

        fun visit(path: Path, visitor: FileVisitor<Path>) {
            path.visitFileTree(visitor)
            path.visitFileTree(visitor, 2, true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.visitFileTree(visitor, maxDepth, followLinks) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileVisitorSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "FileVisitor"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileVisitorOfPathType = types.make(.classType(ClassType(
                classSymbol: fileVisitorSymbol,
                args: [.invariant(pathType)],
                nullability: .nonNull
            )))

            let visitFileTreeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "visitFileTree"].map(interner.intern))
            let visitFileTree = try #require(visitFileTreeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [fileVisitorOfPathType, types.intType, types.booleanType]
                    && signature.returnType == types.unitType
            })
            #expect(symbols.externalLinkName(for: visitFileTree) == "kk_path_visitFileTree")

            let signature = try #require(symbols.functionSignature(for: visitFileTree))
            #expect(signature.valueParameterHasDefaultValues == [false, true, true])
            #expect(signature.valueParameterIsVararg == [false, false, false])
            #expect(signature.valueParameterSymbols.count == 3)
            #expect(interner.resolve(try #require(symbols.symbol(signature.valueParameterSymbols[0])?.name)) == "visitor")
            #expect(interner.resolve(try #require(symbols.symbol(signature.valueParameterSymbols[1])?.name)) == "maxDepth")
            #expect(interner.resolve(try #require(symbols.symbol(signature.valueParameterSymbols[2])?.name)) == "followLinks")

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "visitFileTree", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == visitFileTree)
                #expect(sema.bindings.exprTypes[callExpr] == types.unitType)
            }
        }
    }

    @Test
    func testPathUseLinesRegisteredAsClassMemberOfPath() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useLines

        fun collect(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.useLines class member stubs should register without errors: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let sequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let sequenceOfStringType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let blockType = types.make(.functionType(FunctionType(
                params: [sequenceOfStringType],
                returnType: types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            // useLines is registered as a class member of Path (non-generic, Any return)
            // so Sema can set chosenCallee directly, like File.useLines.
            let useLinesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "Path", "useLines"].map(interner.intern))
            let fullUseLines = try #require(useLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, blockType]
                    && signature.returnType == types.anyType
                    && signature.typeParameterSymbols.isEmpty
            })
            let defaultUseLines = try #require(useLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [blockType]
                    && signature.returnType == types.anyType
                    && signature.typeParameterSymbols.isEmpty
            })
            #expect(symbols.externalLinkName(for: fullUseLines) == "kk_path_useLines")
            #expect(symbols.externalLinkName(for: defaultUseLines) == "kk_path_useLines_default")

            let fullSignature = try #require(symbols.functionSignature(for: fullUseLines))
            #expect(fullSignature.valueParameterHasDefaultValues == [true, false])
            #expect(fullSignature.valueParameterIsVararg == [false, false])
            let defaultSignature = try #require(symbols.functionSignature(for: defaultUseLines))
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(defaultSignature.valueParameterIsVararg == [false])
        }
    }

    @Test
    func testPathReadAttributesStringOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun attributes(path: Path, option: LinkOption): Map<String, Any?> {
            val first: Map<String, Any?> = path.readAttributes("basic:*")
            val second: Map<String, Any?> = path.readAttributes("basic:*", option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.readAttributes(attributes, options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let mapSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Map"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
                classSymbol: mapSymbol,
                args: [.invariant(types.stringType), .out(types.nullableAnyType)],
                nullability: .nonNull
            )))
            let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))
            let readAttributes = try #require(readAttributesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, linkOptionType]
                    && signature.returnType == mapOfStringToNullableAnyType
            })
            #expect(symbols.externalLinkName(for: readAttributes) == "kk_path_readAttributes_string")

            let signature = try #require(symbols.functionSignature(for: readAttributes))
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(signature.valueParameterIsVararg == [false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == readAttributes)
                #expect(sema.bindings.exprTypes[callExpr] == mapOfStringToNullableAnyType)
            }
        }
    }

    @Test
    func testPathUseDirectoryEntriesExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.useDirectoryEntries

        fun collect(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.useDirectoryEntries(glob, block) extension function in kotlin.io.path should register: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let sequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let sequenceOfPathType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
            let useDirectoryEntriesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "useDirectoryEntries"].map(interner.intern))
            let fullUseDirectoryEntries = try #require(useDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let typeParameterType = types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: .nonNull)))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfPathType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, blockType]
                    && signature.returnType == typeParameterType
            })
            let defaultUseDirectoryEntries = try #require(useDirectoryEntriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let typeParameterType = types.make(.typeParam(TypeParamType(symbol: typeParameterSymbol, nullability: .nonNull)))
                let blockType = types.make(.functionType(FunctionType(
                    params: [sequenceOfPathType],
                    returnType: typeParameterType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [blockType]
                    && signature.returnType == typeParameterType
            })
            #expect(symbols.externalLinkName(for: fullUseDirectoryEntries) == "kk_path_useDirectoryEntries")
            #expect(symbols.externalLinkName(for: defaultUseDirectoryEntries) == "kk_path_useDirectoryEntries_default")

            let fullSignature = try #require(symbols.functionSignature(for: fullUseDirectoryEntries))
            #expect(fullSignature.valueParameterHasDefaultValues == [true, false])
            #expect(fullSignature.valueParameterIsVararg == [false, false])
            let defaultSignature = try #require(symbols.functionSignature(for: defaultUseDirectoryEntries))
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(defaultSignature.valueParameterIsVararg == [false])

            #expect(fullSignature.typeParameterSymbols.count == 1)
            #expect(defaultSignature.typeParameterSymbols.count == 1)
        }
    }

    @Test
    func testPathReadAttributesGenericOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.BasicFileAttributes
        import kotlin.io.path.Path
        import kotlin.io.path.readAttributes

        fun attributes(path: Path, option: LinkOption): BasicFileAttributes {
            val first: BasicFileAttributes = path.readAttributes<BasicFileAttributes>()
            val second: BasicFileAttributes = path.readAttributes<BasicFileAttributes>(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.readAttributes<A>(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let basicFileAttributesSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "BasicFileAttributes"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let basicFileAttributesType = types.make(.classType(ClassType(classSymbol: basicFileAttributesSymbol, args: [], nullability: .nonNull)))
            let readAttributesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readAttributes"].map(interner.intern))
            let readAttributes = try #require(readAttributesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                )))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == returnType
            })
            #expect(symbols.externalLinkName(for: readAttributes) == "kk_path_readAttributes")

            let signature = try #require(symbols.functionSignature(for: readAttributes))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.reifiedTypeParameterIndices == [0])
            #expect(signature.typeParameterUpperBoundsList == [[basicFileAttributesType]])
            let typeParameterSymbol = try #require(signature.typeParameterSymbols.first)
            #expect(symbols.symbol(typeParameterSymbol)?.flags.contains(.reifiedTypeParameter) == true)
            #expect(symbols.typeParameterUpperBounds(for: typeParameterSymbol) == [basicFileAttributesType])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readAttributes", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == readAttributes)
                #expect(sema.bindings.exprTypes[callExpr] == basicFileAttributesType)
            }
        }
    }

    @Test
    func testPathTopLevelPathStringFactoryShapeInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path

        fun makePath(): Path {
            return Path("src/main.kt")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path(pathString) top-level factory in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let pathFactorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern))
            let pathFactory = try #require(pathFactorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [types.stringType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: pathFactory) == "kk_path_get")

            let signature = try #require(symbols.functionSignature(for: pathFactory))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])
            let parameterSymbol = try #require(signature.valueParameterSymbols.first)
            #expect(interner.resolve(try #require(symbols.symbol(parameterSymbol)?.name)) == "pathString")

            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else {
                    return false
                }
                return interner.resolve(calleeName) == "Path"
            })
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == pathFactory)
            #expect(sema.bindings.exprTypes[callExpr] == pathType)
        }
    }

    @Test
    func testPathReaderCharsetOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.io.BufferedReader
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.reader
        import kotlin.text.Charsets

        fun readers(path: Path, option: OpenOption): BufferedReader {
            val first: BufferedReader = path.reader()
            val second: BufferedReader = path.reader(Charsets.UTF_8, option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.reader(charset, options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedReaderSymbol = try #require(symbols.lookup(fqName: ["java", "io", "BufferedReader"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedReaderType = types.make(.classType(ClassType(classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull)))
            let readerSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "reader"].map(interner.intern))
            let reader = try #require(readerSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, openOptionType]
                    && signature.returnType == bufferedReaderType
            })
            let defaultReader = try #require(readerSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == []
                    && signature.returnType == bufferedReaderType
            })
            #expect(symbols.externalLinkName(for: reader) == "kk_path_reader")
            #expect(symbols.externalLinkName(for: defaultReader) == "kk_path_reader_default")

            let signature = try #require(symbols.functionSignature(for: reader))
            #expect(signature.valueParameterHasDefaultValues == [true, false])
            #expect(signature.valueParameterIsVararg == [false, true])
            let defaultSignature = try #require(symbols.functionSignature(for: defaultReader))
            #expect(defaultSignature.valueParameterHasDefaultValues == [])
            #expect(defaultSignature.valueParameterIsVararg == [])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "reader", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.contains(defaultReader))
            #expect(chosenCallees.contains(reader))
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == bufferedReaderType)
            }
        }
    }

    @Test
    func testPathSetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.setAttribute

        fun setAttr(path: Path, option: LinkOption): Path {
            return path
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.setAttribute(attribute, value, options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let setAttributeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "setAttribute"].map(interner.intern))
            let setAttribute = try #require(setAttributeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, types.stringType, linkOptionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: setAttribute) == "kk_path_setAttribute")

            let signature = try #require(symbols.functionSignature(for: setAttribute))
            #expect(signature.valueParameterHasDefaultValues == [false, false, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathFileAttributesViewOrNullOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.FileAttributeView
        import kotlin.io.path.Path
        import kotlin.io.path.fileAttributesViewOrNull

        fun <V : FileAttributeView> attributesView(path: Path, option: LinkOption): V? {
            val first: V? = path.fileAttributesViewOrNull<V>()
            val second: V? = path.fileAttributesViewOrNull<V>(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.fileAttributesViewOrNull<V>(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let fileAttributeViewSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttributeView"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let fileAttributeViewType = types.make(.classType(ClassType(classSymbol: fileAttributeViewSymbol, args: [], nullability: .nonNull)))
            let fileAttributesViewOrNullSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileAttributesViewOrNull"].map(interner.intern))
            let fileAttributesViewOrNull = try #require(fileAttributesViewOrNullSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID),
                      let typeParameterSymbol = signature.typeParameterSymbols.first
                else {
                    return false
                }
                let returnType = types.makeNullable(types.make(.typeParam(TypeParamType(
                    symbol: typeParameterSymbol,
                    nullability: .nonNull
                ))))
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == returnType
            })
            #expect(symbols.externalLinkName(for: fileAttributesViewOrNull) == "kk_path_fileAttributesViewOrNull")

            let signature = try #require(symbols.functionSignature(for: fileAttributesViewOrNull))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])
            #expect(signature.typeParameterSymbols.count == 1)
            #expect(signature.typeParameterUpperBoundsList == [[fileAttributeViewType]])
            #expect(symbols.typeParameterUpperBounds(for: try #require(signature.typeParameterSymbols.first)) == [fileAttributeViewType])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "fileAttributesViewOrNull", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == fileAttributesViewOrNull)
                #expect(sema.bindings.exprTypes[callExpr] != nil)
            }
        }
    }

    @Test
    func testPathGetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.getAttribute

        fun attribute(path: Path, option: LinkOption): Any {
            val first = path.getAttribute("size")
            val second = path.getAttribute("lastModifiedTime", option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.getAttribute(attribute, options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let getAttributeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getAttribute"].map(interner.intern))
            let getAttribute = try #require(getAttributeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, linkOptionType]
                    && signature.returnType == types.anyType
            })
            #expect(symbols.externalLinkName(for: getAttribute) == "kk_path_getAttribute")

            let signature = try #require(symbols.functionSignature(for: getAttribute))
            #expect(signature.valueParameterHasDefaultValues == [false, false])
            #expect(signature.valueParameterIsVararg == [false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getAttribute", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == getAttribute)
                #expect(sema.bindings.exprTypes[callExpr] == types.anyType)
            }
        }
    }

    @Test
    func testPathGetOwnerOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.UserPrincipal
        import kotlin.io.path.Path
        import kotlin.io.path.getOwner

        fun owner(path: Path, option: LinkOption): UserPrincipal {
            val first = path.getOwner()
            val second = path.getOwner(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.getOwner(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let userPrincipalSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "UserPrincipal"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let userPrincipalType = types.make(.classType(ClassType(classSymbol: userPrincipalSymbol, args: [], nullability: .nonNull)))
            let getOwnerSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getOwner"].map(interner.intern))
            let getOwner = try #require(getOwnerSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == userPrincipalType
            })
            #expect(symbols.externalLinkName(for: getOwner) == "kk_path_getOwner")

            let signature = try #require(symbols.functionSignature(for: getOwner))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getOwner", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == getOwner)
                #expect(sema.bindings.exprTypes[callExpr] == userPrincipalType)
            }
        }
    }

    @Test
    func testPathMoveToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.CopyOption
        import kotlin.io.path.Path
        import kotlin.io.path.moveTo

        fun movePath(source: Path, target: Path, option: CopyOption): Path {
            val first = source.moveTo(target)
            val second = source.moveTo(target, option)
            val third = source.moveTo(target, true)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.moveTo(target, options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let copyOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "CopyOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let copyOptionType = types.make(.classType(ClassType(classSymbol: copyOptionSymbol, args: [], nullability: .nonNull)))
            let moveToSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "moveTo"].map(interner.intern))
            let optionsMoveTo = try #require(moveToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, copyOptionType]
                    && signature.returnType == pathType
            })
            let overwriteMoveTo = try #require(moveToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, types.booleanType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: optionsMoveTo) == "kk_path_moveTo_options")
            #expect(symbols.externalLinkName(for: overwriteMoveTo) == "kk_path_moveTo_overwrite")

            let optionsSignature = try #require(symbols.functionSignature(for: optionsMoveTo))
            #expect(optionsSignature.valueParameterHasDefaultValues == [false, false])
            #expect(optionsSignature.valueParameterIsVararg == [false, true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "moveTo", in: ast, interner: interner)
            #expect(callExprs.count == 3)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.filter { $0 == optionsMoveTo }.count == 2)
            #expect(chosenCallees.filter { $0 == overwriteMoveTo }.count == 1)
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == pathType)
            }
        }
    }

    @Test
    func testPathIsRegularFileOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.isRegularFile

        fun regularPath(path: Path, option: LinkOption): Boolean {
            val first = path.isRegularFile()
            val second = path.isRegularFile(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.isRegularFile(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let isRegularFileSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "isRegularFile"].map(interner.intern))
            let isRegularFile = try #require(isRegularFileSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            #expect(symbols.externalLinkName(for: isRegularFile) == "kk_path_isRegularFile")

            let signature = try #require(symbols.functionSignature(for: isRegularFile))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "isRegularFile", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == isRegularFile)
                #expect(sema.bindings.exprTypes[callExpr] == types.booleanType)
            }
        }
    }

    @Test
    func testPathExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.exists

        fun presentPath(path: Path, option: LinkOption): Boolean {
            val first = path.exists()
            val second = path.exists(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.exists(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let existsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "exists"].map(interner.intern))
            let exists = try #require(existsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            #expect(symbols.externalLinkName(for: exists) == "kk_path_exists")

            let signature = try #require(symbols.functionSignature(for: exists))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "exists", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == exists)
                #expect(sema.bindings.exprTypes[callExpr] == types.booleanType)
            }
        }
    }

    @Test
    func testPathForEachDirectoryEntryExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.forEachDirectoryEntry

        fun walkEntries(path: Path) {
            path.forEachDirectoryEntry { entry ->
                val text = entry.toString()
            }
            path.forEachDirectoryEntry("*.kt") { entry ->
                val text2 = entry.toString()
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.forEachDirectoryEntry extension functions in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let pathActionType = types.make(.functionType(FunctionType(
                params: [pathType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let forEachSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "forEachDirectoryEntry"].map(interner.intern))
            let globForEachDirectoryEntry = try #require(forEachSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [types.stringType, pathActionType]
                    && signature.returnType == types.unitType
            })
            let defaultForEachDirectoryEntry = try #require(forEachSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathActionType]
                    && signature.returnType == types.unitType
            })
            #expect(symbols.externalLinkName(for: globForEachDirectoryEntry) == "kk_path_forEachDirectoryEntry")
            #expect(symbols.externalLinkName(for: defaultForEachDirectoryEntry) == "kk_path_forEachDirectoryEntry_default")

            let globSignature = try #require(symbols.functionSignature(for: globForEachDirectoryEntry))
            #expect(globSignature.valueParameterHasDefaultValues == [true, false])
            #expect(globSignature.valueParameterIsVararg == [false, false])
            let defaultSignature = try #require(symbols.functionSignature(for: defaultForEachDirectoryEntry))
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(defaultSignature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "forEachDirectoryEntry", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.contains(defaultForEachDirectoryEntry))
            #expect(chosenCallees.contains(globForEachDirectoryEntry))
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == types.unitType)
            }
        }
    }

    @Test
    func testPathNotExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import kotlin.io.path.Path
        import kotlin.io.path.notExists

        fun missingPath(path: Path, option: LinkOption): Boolean {
            val first = path.notExists()
            val second = path.notExists(option)
            return first && second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.notExists(options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let notExistsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "notExists"].map(interner.intern))
            let notExists = try #require(notExistsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == types.booleanType
            })
            #expect(symbols.externalLinkName(for: notExists) == "kk_path_notExists")

            let signature = try #require(symbols.functionSignature(for: notExists))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "notExists", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == notExists)
                #expect(sema.bindings.exprTypes[callExpr] == types.booleanType)
            }
        }
    }

    @Test
    func testPathAppendLinesIterableExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendLines
        import kotlin.text.Charsets

        fun appendPathLines(path: Path, lines: Iterable<CharSequence>): Path {
            val first = path.appendLines(lines)
            val second = path.appendLines(lines, Charsets.UTF_8)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.appendLines Iterable extension function in kotlin.io.path should resolve: \(diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let pathTypeSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("Path")]))
            let charSequenceSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("CharSequence")]))
            let iterableSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Iterable")]))
            let charsetSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("text"), interner.intern("Charset")]))
            let pathType = sema.types.make(.classType(ClassType(classSymbol: pathTypeSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = sema.types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let iterableType = sema.types.make(.classType(ClassType(classSymbol: iterableSymbol, args: [.invariant(charSequenceType)], nullability: .nonNull)))
            let charsetType = sema.types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))

            let appendLinesSymbols = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("io"),
                interner.intern("path"),
                interner.intern("appendLines"),
            ])
            let defaultSymbol = try #require(appendLinesSymbols.first { symbol in
                sema.symbols.functionSignature(for: symbol)?.parameterTypes == [iterableType]
            })
            let charsetOverloadSymbol = try #require(appendLinesSymbols.first { symbol in
                sema.symbols.functionSignature(for: symbol)?.parameterTypes == [iterableType, charsetType]
            })
            let defaultSignature = try #require(sema.symbols.functionSignature(for: defaultSymbol))
            #expect(defaultSignature.receiverType == pathType)
            #expect(defaultSignature.returnType == pathType)
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(sema.symbols.externalLinkName(for: defaultSymbol) == "kk_path_appendLines_iterable_default")

            let charsetSignature = try #require(sema.symbols.functionSignature(for: charsetOverloadSymbol))
            #expect(charsetSignature.receiverType == pathType)
            #expect(charsetSignature.returnType == pathType)
            #expect(charsetSignature.valueParameterHasDefaultValues == [false, false])
            #expect(sema.symbols.externalLinkName(for: charsetOverloadSymbol) == "kk_path_appendLines_iterable")

            let appendLinesCalls = memberCallExprIDs(named: "appendLines", in: ast, interner: interner)
            #expect(appendLinesCalls.count == 2)
            let chosenCallees = appendLinesCalls.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.contains(defaultSymbol))
            #expect(chosenCallees.contains(charsetOverloadSymbol))
            for call in appendLinesCalls {
                #expect(sema.bindings.exprTypes[call] == pathType)
            }
        }
    }

    @Test
    func testPathWriteLinesIterableExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writeLines
        import kotlin.text.Charsets

        fun writePathLines(path: Path, lines: Iterable<CharSequence>, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.writeLines Iterable extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let iterableSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Iterable"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let iterableType = types.make(.classType(ClassType(classSymbol: iterableSymbol, args: [.invariant(charSequenceType)], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let writeLinesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writeLines"].map(interner.intern))
            let writeLines = try #require(writeLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [iterableType, charsetType, openOptionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: writeLines) == "kk_path_writeLines_iterable")

            let signature = try #require(symbols.functionSignature(for: writeLines))
            #expect(signature.valueParameterHasDefaultValues == [false, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathForEachLineExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.forEachLine
        import kotlin.text.Charsets

        fun readLines(path: Path) {
            path.forEachLine { line ->
                val text = line
            }
            path.forEachLine(Charsets.UTF_8) { line ->
                val text = line
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.forEachLine(charset, action) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let stringActionType = types.make(.functionType(FunctionType(
                params: [types.stringType],
                returnType: types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let forEachSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "forEachLine"].map(interner.intern))
            let forEachLine = try #require(forEachSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, stringActionType]
                    && signature.returnType == types.unitType
            })
            let defaultForEachLine = try #require(forEachSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [stringActionType]
                    && signature.returnType == types.unitType
            })
            #expect(symbols.externalLinkName(for: forEachLine) == "kk_path_forEachLine")
            #expect(symbols.externalLinkName(for: defaultForEachLine) == "kk_path_forEachLine_default")

            let signature = try #require(symbols.functionSignature(for: forEachLine))
            #expect(signature.valueParameterHasDefaultValues == [true, false])
            #expect(signature.valueParameterIsVararg == [false, false])
            let defaultSignature = try #require(symbols.functionSignature(for: defaultForEachLine))
            #expect(defaultSignature.valueParameterHasDefaultValues == [false])
            #expect(defaultSignature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "forEachLine", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            let chosenCallees = callExprs.compactMap { sema.bindings.callBinding(for: $0)?.chosenCallee }
            #expect(chosenCallees.contains(defaultForEachLine))
            #expect(chosenCallees.contains(forEachLine))
            for callExpr in callExprs {
                #expect(sema.bindings.exprTypes[callExpr] == types.unitType)
            }
        }
    }

    @Test
    func testPathWriteLinesSequenceExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writeLines
        import kotlin.sequences.Sequence
        import kotlin.text.Charsets

        fun writePathLines(path: Path, lines: Sequence<CharSequence>, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.writeLines Sequence extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charSequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "CharSequence"].map(interner.intern)))
            let sequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charSequenceType = types.make(.classType(ClassType(classSymbol: charSequenceSymbol, args: [], nullability: .nonNull)))
            let sequenceType = types.make(.classType(ClassType(classSymbol: sequenceSymbol, args: [.out(charSequenceType)], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let writeLinesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writeLines"].map(interner.intern))
            let writeLines = try #require(writeLinesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [sequenceType, charsetType, openOptionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: writeLines) == "kk_path_writeLines_sequence")

            let signature = try #require(symbols.functionSignature(for: writeLines))
            #expect(signature.valueParameterHasDefaultValues == [false, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathWriterOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.writer
        import kotlin.text.Charsets

        fun pathWriter(path: Path, option: OpenOption) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.writer(charset, options) extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedWriterSymbol = try #require(symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedWriterType = types.make(.classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull)))
            let writerSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "writer"].map(interner.intern))
            let writer = try #require(writerSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, openOptionType]
                    && signature.returnType == bufferedWriterType
            })
            #expect(symbols.externalLinkName(for: writer) == "kk_path_writer")

            let signature = try #require(symbols.functionSignature(for: writer))
            #expect(signature.valueParameterHasDefaultValues == [true, false])
            #expect(signature.valueParameterIsVararg == [false, true])
        }
    }

    @Test
    func testPathBufferedWriterExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.io.BufferedWriter
        import java.nio.file.OpenOption
        import kotlin.io.path.Path
        import kotlin.io.path.bufferedWriter
        import kotlin.text.Charsets

        fun pathBufferedWriter(path: Path, option: OpenOption): BufferedWriter {
            return path.bufferedWriter(Charsets.UTF_8, 2, option)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.bufferedWriter(charset, bufferSize, options) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let charsetSymbol = try #require(symbols.lookup(fqName: ["kotlin", "text", "Charset"].map(interner.intern)))
            let openOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "OpenOption"].map(interner.intern)))
            let bufferedWriterSymbol = try #require(symbols.lookup(fqName: ["java", "io", "BufferedWriter"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let charsetType = types.make(.classType(ClassType(classSymbol: charsetSymbol, args: [], nullability: .nonNull)))
            let openOptionType = types.make(.classType(ClassType(classSymbol: openOptionSymbol, args: [], nullability: .nonNull)))
            let bufferedWriterType = types.make(.classType(ClassType(classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull)))
            let bufferedWriterSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "bufferedWriter"].map(interner.intern))
            let bufferedWriter = try #require(bufferedWriterSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [charsetType, types.intType, openOptionType]
                    && signature.returnType == bufferedWriterType
            })
            #expect(symbols.externalLinkName(for: bufferedWriter) == "kk_path_bufferedWriter")

            let signature = try #require(symbols.functionSignature(for: bufferedWriter))
            #expect(signature.valueParameterHasDefaultValues == [true, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathFileSizeExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.fileSize

        fun size(path: Path): Long {
            return path.fileSize()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.fileSize extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileSizeSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "fileSize"].map(interner.intern))
            let fileSize = try #require(fileSizeSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == types.longType
            })
            #expect(symbols.externalLinkName(for: fileSize) == "kk_path_fileSize")

            let signature = try #require(symbols.functionSignature(for: fileSize))
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(signature.valueParameterIsVararg == [])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "fileSize", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == fileSize)
            #expect(sema.bindings.exprTypes[callExprs[0]] == types.longType)
        }
    }

    @Test
    func testPathRelativeToOrNullExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeToOrNull

        fun relativePathOrNull(path: Path, base: Path): Path? {
            return path.relativeToOrNull(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.relativeToOrNull extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullablePathType = types.makeNullable(pathType)
            let relativeToOrNullSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeToOrNull"].map(interner.intern))
            let relativeToOrNull = try #require(relativeToOrNullSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == nullablePathType
            })
            #expect(symbols.externalLinkName(for: relativeToOrNull) == "kk_path_relativeToOrNull")

            let signature = try #require(symbols.functionSignature(for: relativeToOrNull))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeToOrNull", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == relativeToOrNull)
            #expect(sema.bindings.exprTypes[callExprs[0]] == nullablePathType)
        }
    }

    @Test
    func testPathSetPosixFilePermissionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.PosixFilePermission
        import kotlin.collections.Set
        import kotlin.io.path.Path
        import kotlin.io.path.setPosixFilePermissions

        fun setPermissions(path: Path, value: Set<PosixFilePermission>): Path {
            return path.setPosixFilePermissions(value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.setPosixFilePermissions extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let setSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Set"].map(interner.intern)))
            let posixFilePermissionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "PosixFilePermission"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let posixFilePermissionType = types.make(.classType(ClassType(classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull)))
            let setOfPosixFilePermissionType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
                nullability: .nonNull
            )))
            let setPosixFilePermissionsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "setPosixFilePermissions"].map(interner.intern))
            let setPosixFilePermissions = try #require(setPosixFilePermissionsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [setOfPosixFilePermissionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: setPosixFilePermissions) == "kk_path_setPosixFilePermissions")

            let signature = try #require(symbols.functionSignature(for: setPosixFilePermissions))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "setPosixFilePermissions", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == setPosixFilePermissions)
            #expect(sema.bindings.exprTypes[callExprs[0]] == pathType)
        }
    }

    @Test
    func testPathGetPosixFilePermissionsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.LinkOption
        import java.nio.file.attribute.PosixFilePermission
        import kotlin.collections.Set
        import kotlin.io.path.Path
        import kotlin.io.path.getPosixFilePermissions

        fun permissions(path: Path, option: LinkOption): Set<PosixFilePermission> {
            val first = path.getPosixFilePermissions()
            val second = path.getPosixFilePermissions(option)
            return second
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.getPosixFilePermissions(options) extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let linkOptionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "LinkOption"].map(interner.intern)))
            let posixFilePermissionSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "PosixFilePermission"].map(interner.intern)))
            let setSymbol = try #require(symbols.lookup(fqName: ["kotlin", "collections", "Set"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let linkOptionType = types.make(.classType(ClassType(classSymbol: linkOptionSymbol, args: [], nullability: .nonNull)))
            let posixFilePermissionType = types.make(.classType(ClassType(classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull)))
            let setOfPosixFilePermissionType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
                nullability: .nonNull
            )))
            let getPosixFilePermissionsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "getPosixFilePermissions"].map(interner.intern))
            let getPosixFilePermissions = try #require(getPosixFilePermissionsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [linkOptionType]
                    && signature.returnType == setOfPosixFilePermissionType
            })
            #expect(symbols.externalLinkName(for: getPosixFilePermissions) == "kk_path_getPosixFilePermissions")

            let signature = try #require(symbols.functionSignature(for: getPosixFilePermissions))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "getPosixFilePermissions", in: ast, interner: interner)
            #expect(callExprs.count == 2)
            for callExpr in callExprs {
                #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == getPosixFilePermissions)
                #expect(sema.bindings.exprTypes[callExpr] == setOfPosixFilePermissionType)
            }
        }
    }

    @Test
    func testOnErrorResultInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.OnErrorResult

        fun nextOnErrorResult(result: OnErrorResult): OnErrorResult {
            return when (result) {
                OnErrorResult.SKIP_SUBTREE -> OnErrorResult.TERMINATE
                OnErrorResult.TERMINATE -> OnErrorResult.SKIP_SUBTREE
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "OnErrorResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathCreateDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createDirectories

        fun create(path: Path, attribute: FileAttribute<*>): Path {
            return path.createDirectories(attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.createDirectories(attributes) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createDirectoriesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createDirectories"].map(interner.intern))
            let createDirectories = try #require(createDirectoriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createDirectories) == "kk_path_createDirectories_attributes")

            let signature = try #require(symbols.functionSignature(for: createDirectories))
            #expect(signature.valueParameterIsVararg == [true])
            #expect(types.nominalTypeParameterSymbols(for: fileAttributeSymbol).count == 1)
        }
    }

    @Test
    func testPathCreateDirectoryAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createDirectory

        fun create(path: Path, attribute: FileAttribute<*>): Path {
            return path.createDirectory(attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.createDirectory(attributes) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createDirectorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createDirectory"].map(interner.intern))
            let createDirectory = try #require(createDirectorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createDirectory) == "kk_path_createDirectory_attributes")

            let signature = try #require(symbols.functionSignature(for: createDirectory))
            #expect(signature.valueParameterIsVararg == [true])
            #expect(types.nominalTypeParameterSymbols(for: fileAttributeSymbol).count == 1)
        }
    }

    @Test
    func testPathCreateFileAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createFile

        fun create(path: Path, attribute: FileAttribute<*>): Path {
            return path.createFile(attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.createFile(attributes) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createFileSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createFile"].map(interner.intern))
            let createFile = try #require(createFileSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createFile) == "kk_path_createFile_attributes")

            let signature = try #require(symbols.functionSignature(for: createFile))
            #expect(signature.valueParameterIsVararg == [true])
            #expect(types.nominalTypeParameterSymbols(for: fileAttributeSymbol).count == 1)
        }
    }

    @Test
    func testPathCreateParentDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createParentDirectories

        fun create(path: Path, attribute: FileAttribute<*>): Path {
            return path.createParentDirectories(attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.createParentDirectories(attributes) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createParentDirectoriesSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createParentDirectories"].map(interner.intern))
            let createParentDirectories = try #require(createParentDirectoriesSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createParentDirectories) == "kk_path_createParentDirectories_attributes")

            let signature = try #require(symbols.functionSignature(for: createParentDirectories))
            #expect(signature.valueParameterIsVararg == [true])
            #expect(types.nominalTypeParameterSymbols(for: fileAttributeSymbol).count == 1)
        }
    }

    @Test
    func testPathDeleteIfExistsExtensionFunctionInIOPathPackageSurfaceMatchesOfficialShape() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.deleteIfExists

        fun delete(path: Path): Boolean {
            return path.deleteIfExists()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.deleteIfExists() extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let deleteIfExistsSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "deleteIfExists"].map(interner.intern))
            let deleteIfExists = try #require(deleteIfExistsSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == []
                    && signature.returnType == types.booleanType
            })
            #expect(symbols.externalLinkName(for: deleteIfExists) == "kk_path_deleteIfExists")

            let annotations = symbols.annotations(for: deleteIfExists)
            #expect(annotations.contains { $0.annotationFQName == "kotlin.IgnorableReturnValue" }, "Path.deleteIfExists should carry @IgnorableReturnValue, got: \(annotations)")
            #expect(annotations.contains { $0.annotationFQName == "kotlin.SinceKotlin" && $0.arguments == ["1.5"] }, "Path.deleteIfExists should carry @SinceKotlin(\"1.5\"), got: \(annotations)")
            #expect(annotations.contains { $0.annotationFQName == "kotlin.Throws" && $0.arguments == ["java.io.IOException::class"] }, "Path.deleteIfExists should carry @Throws(IOException::class), got: \(annotations)")

            let memberSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "Path", "deleteIfExists"].map(interner.intern))
            #expect(!(memberSymbols.contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.receiverType == pathType && signature.parameterTypes.isEmpty
                }), "Path.deleteIfExists should be registered as a kotlin.io.path extension function, not a Path member")
        }
    }

    @Test
    func testPathCreateSymbolicLinkPointingToAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createSymbolicLinkPointingTo

        fun link(linkPath: Path, target: Path, attribute: FileAttribute<*>): Path {
            return linkPath.createSymbolicLinkPointingTo(target, attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.createSymbolicLinkPointingTo(target, attributes) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createLinkSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createSymbolicLinkPointingTo"].map(interner.intern))
            let createLink = try #require(createLinkSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createLink) == "kk_path_createSymbolicLinkPointingTo_attributes")

            let signature = try #require(symbols.functionSignature(for: createLink))
            #expect(signature.valueParameterIsVararg == [false, true])
        }
    }

    @Test
    func testCreateTempDirectoryDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun create(directory: Path, attribute: FileAttribute<*>): Path {
            return createTempDirectory(directory, "kswiftk-", attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "createTempDirectory(directory, prefix, attributes) top-level function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullablePathType = types.makeNullable(pathType)
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createTempDirectorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern))
            let createTempDirectory = try #require(createTempDirectorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [nullablePathType, nullableStringType, fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createTempDirectory) == "kk_path_createTempDirectory_directory_prefix_attributes")

            let signature = try #require(symbols.functionSignature(for: createTempDirectory))
            #expect(signature.valueParameterHasDefaultValues == [false, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testCreateTempDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createTempDirectory

        fun create(attribute: FileAttribute<*>): Path {
            return createTempDirectory("kswiftk-", attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "createTempDirectory(prefix, attributes) top-level function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createTempDirectorySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createTempDirectory"].map(interner.intern))
            let createTempDirectory = try #require(createTempDirectorySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [nullableStringType, fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createTempDirectory) == "kk_path_createTempDirectory_prefix_attributes")

            let signature = try #require(symbols.functionSignature(for: createTempDirectory))
            #expect(signature.valueParameterHasDefaultValues == [true, false])
            #expect(signature.valueParameterIsVararg == [false, true])
        }
    }

    @Test
    func testCreateTempFileDirectoryPrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createTempFile

        fun create(directory: Path, attribute: FileAttribute<*>): Path {
            return createTempFile(directory, "kswiftk-", ".data", attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "createTempFile(directory, prefix, suffix, attributes) top-level function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullablePathType = types.makeNullable(pathType)
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createTempFileSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createTempFile"].map(interner.intern))
            let createTempFile = try #require(createTempFileSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [nullablePathType, nullableStringType, nullableStringType, fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createTempFile) == "kk_path_createTempFile_directory_prefix_suffix_attributes")

            let signature = try #require(symbols.functionSignature(for: createTempFile))
            #expect(signature.valueParameterHasDefaultValues == [false, true, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, false, true])
        }
    }

    @Test
    func testCreateTempFilePrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import java.nio.file.attribute.FileAttribute
        import kotlin.io.path.Path
        import kotlin.io.path.createTempFile

        fun create(attribute: FileAttribute<*>): Path {
            return createTempFile("kswiftk-", ".data", attribute)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "createTempFile(prefix, suffix, attributes) top-level function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let fileAttributeSymbol = try #require(symbols.lookup(fqName: ["java", "nio", "file", "attribute", "FileAttribute"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let nullableStringType = types.makeNullable(types.stringType)
            let fileAttributeStarType = types.make(.classType(ClassType(
                classSymbol: fileAttributeSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            let createTempFileSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "createTempFile"].map(interner.intern))
            let createTempFile = try #require(createTempFileSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == nil
                    && signature.parameterTypes == [nullableStringType, nullableStringType, fileAttributeStarType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: createTempFile) == "kk_path_createTempFile_prefix_suffix_attributes")

            let signature = try #require(symbols.functionSignature(for: createTempFile))
            #expect(signature.valueParameterHasDefaultValues == [true, true, false])
            #expect(signature.valueParameterIsVararg == [false, false, true])
        }
    }

    @Test
    func testPathCopyToRecursivelyOverwriteExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(source: Path, target: Path, onError: (Path, Path, Exception) -> OnErrorResult): Path {
            return source.copyToRecursively(target, onError, true, true)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.copyToRecursively(target, onError, followLinks, overwrite) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let exceptionSymbol = try #require(symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern)))
            let onErrorResultSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let exceptionType = types.make(.classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull)))
            let onErrorResultType = types.make(.classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull)))
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern))
            let copyToRecursively = try #require(copySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, types.booleanType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: copyToRecursively) == "kk_path_copyToRecursively_overwrite")
        }
    }

    @Test
    func testPathCopyToRecursivelyCopyActionExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.Exception
        import kotlin.io.path.CopyActionContext
        import kotlin.io.path.CopyActionResult
        import kotlin.io.path.OnErrorResult
        import kotlin.io.path.Path
        import kotlin.io.path.copyToRecursively

        fun copyTree(
            source: Path,
            target: Path,
            onError: (Path, Path, Exception) -> OnErrorResult,
            copyAction: CopyActionContext.(Path, Path) -> CopyActionResult
        ): Path {
            return source.copyToRecursively(target, onError, true, copyAction)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.copyToRecursively(target, onError, followLinks, copyAction) extension function in kotlin.io.path should resolve: \(diagnostics)")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let exceptionSymbol = try #require(symbols.lookup(fqName: ["kotlin", "Exception"].map(interner.intern)))
            let onErrorResultSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "OnErrorResult"].map(interner.intern)))
            let copyActionContextSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionContext"].map(interner.intern)))
            let copyActionResultSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "CopyActionResult"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let exceptionType = types.make(.classType(ClassType(classSymbol: exceptionSymbol, args: [], nullability: .nonNull)))
            let onErrorResultType = types.make(.classType(ClassType(classSymbol: onErrorResultSymbol, args: [], nullability: .nonNull)))
            let copyActionContextType = types.make(.classType(ClassType(classSymbol: copyActionContextSymbol, args: [], nullability: .nonNull)))
            let copyActionResultType = types.make(.classType(ClassType(classSymbol: copyActionResultSymbol, args: [], nullability: .nonNull)))
            let onErrorType = types.make(.functionType(FunctionType(
                params: [pathType, pathType, exceptionType],
                returnType: onErrorResultType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copyActionType = types.make(.functionType(FunctionType(
                receiver: copyActionContextType,
                params: [pathType, pathType],
                returnType: copyActionResultType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copySymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "copyToRecursively"].map(interner.intern))
            let copyToRecursively = try #require(copySymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else {
                    return false
                }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType, onErrorType, types.booleanType, copyActionType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: copyToRecursively) == "kk_path_copyToRecursively_copyAction")
        }
    }

    @Test
    func testPathReadSymbolicLinkExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.readSymbolicLink

        fun readLinkTarget(path: Path): Path {
            return path.readSymbolicLink()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.readSymbolicLink extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let readSymbolicLinkSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "readSymbolicLink"].map(interner.intern))
            let readSymbolicLink = try #require(readSymbolicLinkSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes.isEmpty
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: readSymbolicLink) == "kk_path_readSymbolicLink")

            let signature = try #require(symbols.functionSignature(for: readSymbolicLink))
            #expect(signature.valueParameterHasDefaultValues == [])
            #expect(signature.valueParameterIsVararg == [])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "readSymbolicLink", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == readSymbolicLink)
            #expect(sema.bindings.exprTypes[callExprs[0]] == pathType)
        }
    }

    @Test
    func testPathRelativeToOrSelfExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeToOrSelf

        fun relativePathOrSelf(path: Path, base: Path): Path {
            return path.relativeToOrSelf(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.relativeToOrSelf extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let relativeToOrSelfSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeToOrSelf"].map(interner.intern))
            let relativeToOrSelf = try #require(relativeToOrSelfSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: relativeToOrSelf) == "kk_path_relativeToOrSelf")

            let signature = try #require(symbols.functionSignature(for: relativeToOrSelf))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeToOrSelf", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == relativeToOrSelf)
            #expect(sema.bindings.exprTypes[callExprs[0]] == pathType)
        }
    }

    @Test
    func testPathRelativeToExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.relativeTo

        fun relativePath(path: Path, base: Path): Path {
            return path.relativeTo(base)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.relativeTo extension function in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let relativeToSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "relativeTo"].map(interner.intern))
            let relativeTo = try #require(relativeToSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [pathType]
                    && signature.returnType == pathType
            })
            #expect(symbols.externalLinkName(for: relativeTo) == "kk_path_relativeTo")

            let signature = try #require(symbols.functionSignature(for: relativeTo))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [false])

            let ast = try #require(ctx.ast)
            let callExprs = memberCallExprIDs(named: "relativeTo", in: ast, interner: interner)

            #expect(callExprs.count == 1)
            #expect(sema.bindings.callBinding(for: callExprs[0])?.chosenCallee == relativeTo)
            #expect(sema.bindings.exprTypes[callExprs[0]] == pathType)
        }
    }

    @Test
    func testPathWalkOptionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.PathWalkOption

        fun nextPathWalkOption(option: PathWalkOption): PathWalkOption {
            return when (option) {
                PathWalkOption.BREADTH_FIRST -> PathWalkOption.FOLLOW_LINKS
                PathWalkOption.FOLLOW_LINKS -> PathWalkOption.BREADTH_FIRST
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "PathWalkOption entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathWalkOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.PathWalkOption
        import kotlin.io.path.walk
        import kotlin.sequences.Sequence

        fun walkPath(path: Path) {}
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.walk(options) extension function in kotlin.io.path should register: \(ctx.diagnostics.diagnostics.map(\.message))")

            let interner = ctx.interner
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let pathSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "Path"].map(interner.intern)))
            let walkOptionSymbol = try #require(symbols.lookup(fqName: ["kotlin", "io", "path", "PathWalkOption"].map(interner.intern)))
            let sequenceSymbol = try #require(symbols.lookup(fqName: ["kotlin", "sequences", "Sequence"].map(interner.intern)))
            let pathType = types.make(.classType(ClassType(classSymbol: pathSymbol, args: [], nullability: .nonNull)))
            let walkOptionType = types.make(.classType(ClassType(classSymbol: walkOptionSymbol, args: [], nullability: .nonNull)))
            let sequenceOfPathType = types.make(.classType(ClassType(
                classSymbol: sequenceSymbol,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
            let walkSymbols = symbols.lookupAll(fqName: ["kotlin", "io", "path", "walk"].map(interner.intern))
            let walk = try #require(walkSymbols.first { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == pathType
                    && signature.parameterTypes == [walkOptionType]
                    && signature.returnType == sequenceOfPathType
            })
            #expect(symbols.externalLinkName(for: walk) == "kk_path_walk")

            let signature = try #require(symbols.functionSignature(for: walk))
            #expect(signature.valueParameterHasDefaultValues == [false])
            #expect(signature.valueParameterIsVararg == [true])
        }
    }

    @Test
    func testPathInvariantSeparatorsPathStringPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.invariantSeparatorsPathString

        fun invariantSeparators(path: Path): String {
            val normalized: String = path.invariantSeparatorsPathString
            return normalized
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.invariantSeparatorsPathString in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathInvariantSeparatorsPathPropertyInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.invariantSeparatorsPath

        fun invariantSeparators(path: Path): String {
            val normalized: String = path.invariantSeparatorsPath
            return normalized
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Path.invariantSeparatorsPath in kotlin.io.path should resolve as String: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testPathAbsoluteExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.absolute

        fun pathAbsolute(path: Path) {
            path.absolute()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let pathFQName = ["kotlin", "io", "path", "Path"].map { ctx.interner.intern($0) }
            let pathSymbol = try #require(sema.symbols.lookup(fqName: pathFQName))
            let pathType = sema.types.make(.classType(ClassType(
                classSymbol: pathSymbol,
                args: [],
                nullability: .nonNull
            )))
            let absoluteFQName = ["kotlin", "io", "path", "absolute"].map { ctx.interner.intern($0) }
            let absoluteSymbol = try #require(sema.symbols.lookupAll(fqName: absoluteFQName).first(where: { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.receiverType == pathType
                }))
            let absoluteSignature = try #require(sema.symbols.functionSignature(for: absoluteSymbol))
            #expect(absoluteSignature.parameterTypes == [])
            #expect(absoluteSignature.returnType == pathType)
            #expect(!(ctx.diagnostics.hasError), "Path.absolute extension function in kotlin.io.path should resolve as Path: \(ctx.diagnostics.diagnostics.map(\.message))")
            let ast = try #require(ctx.ast)
            let callExpr = try #require(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, calleeName, _, _, _) = expr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "absolute"
            })
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == absoluteSymbol)
            #expect(sema.bindings.exprTypes[callExpr] == pathType)
        }
    }

    @Test
    func testPathAbsolutePathStringExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.absolutePathString

        fun pathAbsolutePathString(path: Path): String {
            return path.absolutePathString()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            let sema = try #require(ctx.sema)
            let astAbs = try #require(ctx.ast)
            let interner = ctx.interner
            let pathSymbolAbs = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    interner.intern("path"),
                    interner.intern("Path"),
                ]))
            let pathTypeAbs = sema.types.make(.classType(ClassType(
                classSymbol: pathSymbolAbs,
                args: [],
                nullability: .nonNull
            )))
            let absolutePathStringSymbol = try #require(sema.symbols.lookup(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    interner.intern("path"),
                    interner.intern("absolutePathString"),
                ]))
            let signature = try #require(sema.symbols.functionSignature(for: absolutePathStringSymbol))
            #expect(signature.receiverType == pathTypeAbs)
            #expect(signature.parameterTypes == [])
            #expect(signature.returnType == sema.types.stringType)
            #expect(!(ctx.diagnostics.hasError), "Path.absolutePathString() in kotlin.io.path should resolve as String: \(diagnostics)")

            let callExpr = try #require(memberCallExprIDs(named: "absolutePathString", in: astAbs, interner: interner).first)
            #expect(sema.bindings.callBinding(for: callExpr)?.chosenCallee == absolutePathStringSymbol)
            #expect(sema.bindings.exprTypes[callExpr] == sema.types.stringType)
        }
    }

    @Test
    func testPathAppendBytesExtensionFunctionInIOPathPackageSurfaceIsResolved() throws {
        let source = """
        import kotlin.io.path.Path
        import kotlin.io.path.appendBytes

        fun appendPathBytes(path: Path, bytes: ByteArray) {
            path.appendBytes(bytes)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
            #expect(!(ctx.diagnostics.hasError), "Path.appendBytes extension function in kotlin.io.path should resolve: \(diagnostics)")

            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let interner = ctx.interner
            let pathTypeSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("Path")]))
            let byteArraySymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("ByteArray")]))
            let pathType = sema.types.make(.classType(ClassType(classSymbol: pathTypeSymbol, args: [], nullability: .nonNull)))
            let byteArrayType = sema.types.make(.classType(ClassType(classSymbol: byteArraySymbol, args: [], nullability: .nonNull)))
            let appendBytesSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("io"), interner.intern("path"), interner.intern("appendBytes")]))
            let signature = try #require(sema.symbols.functionSignature(for: appendBytesSymbol))
            #expect(signature.receiverType == pathType)
            #expect(signature.parameterTypes == [byteArrayType])
            #expect(signature.returnType == sema.types.unitType)
            #expect(sema.symbols.externalLinkName(for: appendBytesSymbol) == "kk_path_appendBytes")

            let appendBytesCall = try #require(memberCallExprIDs(named: "appendBytes", in: ast, interner: interner).first)
            #expect(sema.bindings.callBinding(for: appendBytesCall)?.chosenCallee == appendBytesSymbol)
            #expect(sema.bindings.exprTypes[appendBytesCall] == sema.types.unitType)
        }
    }

    @Test
    func testMemoryOrderInAtomicsPackageIsResolved() throws {
        let source = """
        import kotlin.concurrent.atomics.MemoryOrder

        fun main() {
            val order = MemoryOrder.SEQUENTIALLY_CONSISTENT
            println(order)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!(ctx.diagnostics.hasError), "MemoryOrder in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
        }
    }

    @Test
    func testTypeSystemLUBAndGLB() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))
        let boolNN = types.make(.primitive(.boolean, .nonNull))

        #expect(types.lub([]) == types.errorType)
        #expect(types.lub([intNN, intNN]) == intNN)
        #expect(types.lub([intNN, intNullable]) == types.nullableAnyType)

        #expect(types.glb([]) == types.errorType)
        #expect(types.glb([intNN, intNN]) == intNN)
        #expect(types.glb([intNN, types.nothingType]) == types.nothingType)

        let glbMixed = types.glb([intNN, boolNN])
        #expect(types.kind(of: glbMixed) == .intersection([intNN, boolNN]))

        #expect(types.kind(of: TypeID(rawValue: 9999)) == .error)
    }

    @Test
    func testTypeSystemAnyNonNullSubtypeCoversClassFunctionIntersectionAndDefaultCases() {
        let types = TypeSystem()

        let intNN = types.make(.primitive(.int, .nonNull))
        let intNullable = types.make(.primitive(.int, .nullable))

        let classNN = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nonNull
        )))
        let classNullable = types.make(.classType(ClassType(
            classSymbol: SymbolID(rawValue: 400),
            args: [],
            nullability: .nullable
        )))

        let fnNN = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnNullable = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nullable
        )))

        let intersectionAllNonNull = types.make(.intersection([intNN, classNN]))
        let intersectionWithNullable = types.make(.intersection([intNN, intNullable]))

        #expect(types.isSubtype(classNN, types.anyType))
        #expect(!(types.isSubtype(classNullable, types.anyType)))
        #expect(types.isSubtype(fnNN, types.anyType))
        #expect(!(types.isSubtype(fnNullable, types.anyType)))
        #expect(types.isSubtype(intersectionAllNonNull, types.anyType))
        // With corrected intersection subtype rules (P5-97): A & B <: C if ANY part <: C.
        // intersection([Int, Int?]) <: Any is true because Int <: Any.
        #expect(types.isSubtype(intersectionWithNullable, types.anyType))
        #expect(!(types.isSubtype(types.nullableAnyType, types.anyType)))

        let fnWithReceiver = types.make(.functionType(FunctionType(
            receiver: intNN,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        let fnWithoutReceiver = types.make(.functionType(FunctionType(
            receiver: nil,
            params: [intNN],
            returnType: intNN,
            isSuspend: false,
            nullability: .nonNull
        )))
        #expect(!(types.isSubtype(fnWithReceiver, fnWithoutReceiver)))
    }

    @Test
    func testSemanticsBindingTableAndSymbolTableScopes() {
        let interner = StringInterner()
        let symbols = SymbolTable()

        let pkg = symbols.define(
            kind: .package,
            name: interner.intern("pkg"),
            fqName: [interner.intern("pkg")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        let fn = symbols.define(
            kind: .function,
            name: interner.intern("run"),
            fqName: [interner.intern("pkg"), interner.intern("run")],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction, .suspendFunction]
        )

        #expect(symbols.count == 2)
        #expect(symbols.symbol(pkg)?.kind == .package)
        #expect(symbols.lookup(fqName: [interner.intern("pkg")]) == pkg)

        let signature = FunctionSignature(parameterTypes: [TypeSystem().anyType], returnType: TypeSystem().unitType)
        symbols.setFunctionSignature(signature, for: fn)
        #expect(symbols.functionSignature(for: fn)?.parameterTypes.count == 1)

        let root = PackageScope(parent: nil, symbols: symbols)
        let fileScope = FileScope(parent: root, symbols: symbols)
        fileScope.insert(fn)
        #expect(fileScope.lookup(interner.intern("run")) == [fn])
        #expect(root.lookup(interner.intern("run")).isEmpty)

        let bindings = BindingTable()
        let expr = ExprID(rawValue: 1)
        let decl = DeclID(rawValue: 2)
        bindings.bindExprType(expr, type: TypeSystem().anyType)
        bindings.bindIdentifier(expr, symbol: fn)
        bindings.bindCall(expr, binding: CallBinding(chosenCallee: fn, substitutedTypeArguments: [], parameterMapping: [0: 0]))
        bindings.bindCallableTarget(expr, target: .symbol(fn))
        bindings.bindCallableValueCall(
            expr,
            binding: CallableValueCallBinding(
                target: .localValue(fn),
                functionType: TypeSystem().anyType,
                parameterMapping: [0: 0]
            )
        )
        bindings.bindCallableTarget(expr, target: .localValue(fn))
        bindings.bindCaptureSymbols(expr, symbols: [fn, fn])
        bindings.bindDecl(decl, symbol: fn)
        bindings.bindCatchClause(expr, binding: CatchClauseBinding(parameterSymbol: fn, parameterType: TypeSystem().anyType))

        #expect(bindings.identifierSymbol(for: expr) == fn)
        #expect(bindings.callBinding(for: expr)?.chosenCallee == fn)
        #expect(bindings.callableTarget(for: expr) == .localValue(fn))
        #expect(bindings.callableValueCallBinding(for: expr)?.parameterMapping == [0: 0])
        #expect(bindings.catchClauseBinding(for: expr)?.parameterSymbol == fn)
        #expect(bindings.captureSymbols(for: expr) == [fn])
        #expect(bindings.declSymbol(for: decl) == fn)
        #expect(!(bindings.isSuperCallExpr(expr)))
    }

    @Test
    func testImportAliasDeclStoresAliasField() {
        let interner = StringInterner()
        let range = makeRange(start: 0, end: 10)

        let noAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: nil)
        #expect(noAlias.alias == nil)

        let withAlias = ImportDecl(range: range, path: [interner.intern("a"), interner.intern("B")], alias: interner.intern("X"))
        #expect(withAlias.alias == interner.intern("X"))
    }

    @Test
    func testConditionBranchStructCreation() {
        let analyzer = DataFlowAnalyzer()
        let sym = SymbolID(rawValue: 100)
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))
        let stringType = types.stringType

        let trueState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [intType], nullability: .nonNull, isStable: true),
        ])
        let falseState = DataFlowState(variables: [
            sym: VariableFlowState(possibleTypes: [stringType], nullability: .nonNull, isStable: true),
        ])
        let branch = ConditionBranch(trueState: trueState, falseState: falseState)

        #expect(branch.trueState.variables[sym]?.possibleTypes == [intType])
        #expect(branch.falseState.variables[sym]?.possibleTypes == [stringType])

        let merged = analyzer.merge(branch.trueState, branch.falseState)
        #expect(merged.variables[sym]?.possibleTypes.count == 2)
        #expect(merged.variables[sym]?.possibleTypes.contains(intType) == true)
        #expect(merged.variables[sym]?.possibleTypes.contains(stringType) == true)
    }
}

@Suite @MainActor
struct CommandRunnerErrorPathTests {
    @Test
    func testRunReturnsStdoutOnSuccess() throws {
        let result = try CommandRunner.run(
            executable: "/usr/bin/env",
            arguments: ["sh", "-c", "printf 'ok'"]
        )

        #expect(result.exitCode == 0)
        #expect(result.stdout == "ok")
    }

    @Test
    func testRunThrowsNonZeroExitWithCapturedStderr() throws {
        do {
            try CommandRunner.run(
                executable: "/usr/bin/env",
                arguments: ["sh", "-c", "printf 'err' >&2; exit 7"]
            )
            Issue.record("expected throw")
        } catch {
            guard case let CommandRunnerError.nonZeroExit(result) = error else {
                Issue.record("Expected nonZeroExit, got \(error)")
                return
            }
            #expect(result.exitCode == 7)
            #expect(result.stderr == "err")
        }
    }

    @Test
    func testRunThrowsLaunchFailedForMissingExecutable() throws {
        do {
            try CommandRunner.run(
                executable: "/definitely/missing/executable",
                arguments: []
            )
            Issue.record("expected throw")
        } catch {
            guard case let CommandRunnerError.launchFailed(message) = error else {
                Issue.record("Expected launchFailed, got \(error)")
                return
            }
            #expect(message.contains("Failed to launch"))
        }
    }
}
