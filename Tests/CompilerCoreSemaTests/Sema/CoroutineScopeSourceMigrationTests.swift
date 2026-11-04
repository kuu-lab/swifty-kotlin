#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct CoroutineScopeSourceMigrationTests {
    @Test
    func unrelatedImportDoesNotHideCoroutineSuspendBuilders() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*
        import java.util.LinkedList

        suspend fun probe() {
            coroutineScope {
                supervisorScope {
                    withTimeout(1L) {
                        delay(1L)
                        async { 7 }.await()
                    }
                }
            }
        }
        """, allowDefaultStdlibLibrary: true)
        #expect(ctx.options.stdlibLibraryPath != nil)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func scopeBuildersAcceptReceiverFunctionValuesAndLiterals() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*

        suspend fun throughCoroutine(block: suspend CoroutineScope.() -> Int): Int =
            coroutineScope(block = block)
        suspend fun throughSupervisor(block: suspend CoroutineScope.() -> Int): Int =
            supervisorScope(block)

        suspend fun probe(block: suspend CoroutineScope.() -> Int) {
            coroutineScope(block = block)
            supervisorScope(block)
            coroutineScope {
                val scope: CoroutineScope = this
                scope.ensureActive()
                async { 7 }.await()
            }
            supervisorScope {
                val scope: CoroutineScope = this
                scope.launch { }.join()
                coroutineContext.isActive
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let scopeSymbol = try #require(sema.symbols.lookupAll(
            fqName: ["kotlinx", "coroutines", "CoroutineScope"].map(ctx.interner.intern)
        ).first { sema.symbols.symbol($0)?.kind == .interface })
        for name in ["coroutineScope", "supervisorScope"] {
            let symbol = try #require(sema.symbols.lookupAll(
                fqName: ["kotlinx", "coroutines", name].map(ctx.interner.intern)
            ).first { sema.symbols.symbol($0)?.kind == .function })
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            let blockType = try #require(signature.parameterTypes.first)
            guard case let .functionType(block) = sema.types.kind(of: blockType) else {
                Issue.record("Expected a function-typed block")
                continue
            }
            let receiver = try #require(block.receiver)
            guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                Issue.record("Expected a CoroutineScope receiver")
                continue
            }
            #expect(receiverClass.classSymbol == scopeSymbol)
            #expect(block.isSuspend)
            #expect(block.params.isEmpty)
        }
    }

    @Test
    func scopeBuildersAreGenericOverBlockResult() throws {
        // KUU-4095: upstream declares `suspend fun <R> coroutineScope/
        // supervisorScope(block: suspend CoroutineScope.() -> R): R`; the
        // bundled declarations must match so explicit type arguments and the
        // block's result type flow through the signature.
        let ctx = makeContextFromSource("""
        import kotlinx.coroutines.*

        suspend fun probe() {
            val scopedIntExplicit: Int = coroutineScope<Int> { 5 }
            val supervisedIntExplicit: Int = supervisorScope<Int> { 6 }
            val scopedIntInferred = coroutineScope { 7 }
            val supervisedStrInferred = supervisorScope { "y" }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        for name in ["coroutineScope", "supervisorScope"] {
            let symbol = try #require(sema.symbols.lookupAll(
                fqName: ["kotlinx", "coroutines", name].map(ctx.interner.intern)
            ).first { sema.symbols.symbol($0)?.kind == .function })
            let signature = try #require(sema.symbols.functionSignature(for: symbol))
            #expect(signature.typeParameterSymbols.count == 1, "\(name) should declare one type parameter")
            guard case let .typeParam(returnParam) = sema.types.kind(of: signature.returnType) else {
                Issue.record("Expected \(name) to return its type parameter")
                continue
            }
            #expect(signature.typeParameterSymbols.contains(returnParam.symbol))
            let blockType = try #require(signature.parameterTypes.first)
            guard case let .functionType(block) = sema.types.kind(of: blockType),
                  case let .typeParam(blockReturn) = sema.types.kind(of: block.returnType) else {
                Issue.record("Expected \(name)'s block to return the type parameter")
                continue
            }
            #expect(blockReturn.symbol == returnParam.symbol)
        }
        // Explicit and inferred call results bind to the block's result type.
        let ast = try #require(ctx.ast)
        let probedNames: Set<String> = [
            "scopedIntExplicit", "supervisedIntExplicit",
            "scopedIntInferred", "supervisedStrInferred",
        ]
        var bound: [String: String] = [:]
        for index in ast.arena.exprs.indices {
            let expr = ExprID(rawValue: Int32(index))
            guard case let .localDecl(name, _, _, initializer, _, _, _) = ast.arena.expr(expr),
                  let initializer,
                  probedNames.contains(ctx.interner.resolve(name)),
                  let type = sema.bindings.exprType(for: initializer) else { continue }
            bound[ctx.interner.resolve(name)] = sema.types.renderType(type)
        }
        #expect(bound == [
            "scopedIntExplicit": "Int",
            "supervisedIntExplicit": "Int",
            "scopedIntInferred": "Int",
            "supervisedStrInferred": "String",
        ])
    }

    @Test
    func mismatchedExplicitScopeResultIsRejected() throws {
        // KUU-4095: a generic signature enforces the declared result instead
        // of silently coercing Any?.
        for statement in [
            "val x: Int = coroutineScope<Int> { \"nope\" }",
            "val x: Int = supervisorScope<Int> { \"nope\" }",
            "val x: String = coroutineScope { 5 }",
        ] {
            let ctx = makeContextFromSource("""
            import kotlinx.coroutines.*

            suspend fun probe() {
                \(statement)
            }
            """)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected rejection of `\(statement)`")
        }
    }

    @Test
    func factoriesAndHelpersUseBundledDeclarations() throws {
        let ctx = makeContextFromSource("""
        import kotlin.coroutines.EmptyCoroutineContext
        import kotlinx.coroutines.*

        suspend fun probe() {
            val job: CompletableJob = Job()
            SupervisorJob(job)
            job.complete()
            val scope = CoroutineScope(EmptyCoroutineContext)
            scope.ensureActive()
            scope.cancel()
            scope.coroutineContext.ensureActive()
            scope.coroutineContext.cancel()
            currentCoroutineContext()
            MainScope().cancel()
            println(GlobalScope.isActive)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let package = ["kotlinx", "coroutines"].map(ctx.interner.intern)
        #expect(sema.symbols.lookupAll(fqName: ["kotlin", "coroutines", "CoroutineContext", "cancel"].map(ctx.interner.intern)).isEmpty)

        for name in ["Job", "SupervisorJob", "CoroutineScope", "MainScope", "currentCoroutineContext"] {
            let symbol = try #require(sema.symbols.lookupAll(fqName: package + [ctx.interner.intern(name)]).first {
                sema.symbols.symbol($0)?.kind == .function
            })
            #expect(sema.symbols.isSourceBackedSymbol(symbol), "\(name) should be source backed")
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        }

        let activeProperties = sema.symbols.lookupAll(fqName: package + [ctx.interner.intern("isActive")]).filter {
            sema.symbols.extensionPropertyReceiverType(for: $0) != nil
        }
        #expect(activeProperties.count == 2)
        #expect(Set(activeProperties.compactMap { sema.symbols.extensionPropertyReceiverType(for: $0) }).count == 2)
        for property in activeProperties {
            #expect(sema.symbols.isSourceBackedSymbol(property))
            #expect(sema.symbols.extensionPropertyGetterAccessor(for: property) != nil)
            #expect(sema.symbols.externalLinkName(for: property) == nil)
        }
    }

    @Test
    func extensionPropertiesWithDifferentReceiversKeepSeparateSymbols() throws {
        let ctx = makeContextFromSource("""
        package sample
        class First
        class Second
        val First.active: Boolean get() = true
        val Second.active: Boolean get() = false
        fun probe(first: First, second: Second) {
            println(first.active)
            println(second.active)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let properties = sema.symbols.lookupAll(fqName: ["sample", "active"].map(ctx.interner.intern))
        #expect(properties.count == 2)
        #expect(Set(properties.compactMap { sema.symbols.extensionPropertyReceiverType(for: $0) }).count == 2)
    }
}
#endif
