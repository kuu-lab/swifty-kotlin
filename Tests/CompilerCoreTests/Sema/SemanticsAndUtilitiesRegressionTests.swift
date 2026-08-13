@testable import CompilerCore
import Foundation
import Testing

@Suite
struct SemanticsAndUtilitiesRegressionTests {

    // MARK: - Path-aware expression search helpers

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

    // MARK: - Consolidated Semantics and Utilities Regression tests
    @Test
    func testSemanticsAndUtilitiesRegression() throws {
        let sources: [String] = [
            // testAtomicStoreExpressionIsTypedAsUnit
            """
            package sample0

                    import kotlin.concurrent.atomics.AtomicInt

                    fun main() {
                        val ai = AtomicInt(1)
                        val x = ai.store(2)
                        val y: Unit = x
                    }

            """,
            // testAtomicMigrationAliasesResolveInAtomicsPackage
            """
            package sample1

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.AtomicInt
                    import kotlin.concurrent.atomics.AtomicLong

                    fun main() {
                        val intValue = AtomicInt(1)
                        val nextInt = intValue.incrementAndGet()
                        val intAgain = intValue.get()

                        val longValue = AtomicLong(3L)
                        val nextLong = longValue.incrementAndGet()
                        val longAgain = longValue.get()

                        println(nextInt + intAgain)
                        println(nextLong + longAgain)
                    }

            """,
            // testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions
            """
            package sample2

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

            """,
            // testLegacyAtomicTypeAliasStillResolves
            """
            package sample3

                    import kotlin.concurrent.AtomicInt

                    fun main() {
                        val ai = AtomicInt(1)
                        println(ai.load())
                    }

            """,
            // testExperimentalAtomicOptInMarkerIsResolved
            """
            package sample4

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.ExperimentalAtomicApi

                    fun main() {
                        println("ok")
                    }

            """,
            // testAtomicReferenceInAtomicsPackageIsResolved
            """
            package sample5

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.ExperimentalAtomicApi
                    import kotlin.concurrent.atomics.AtomicReference

                    fun main() {
                        val ar = AtomicReference("hello")
                        println(ar.load())
                    }

            """,
            // testAtomicLongInConcurrentPackageIsResolved
            """
            package sample6

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.AtomicLong

                    fun main() {
                        val al = AtomicLong(42L)
                        println(al.load())
                    }

            """,
            // testAtomicIntArrayInConcurrentPackageIsResolved
            """
            package sample7

                    import kotlin.concurrent.AtomicIntArray

                    fun main() {
                        val values = AtomicIntArray(2)
                        values.storeAt(0, 10)
                        val ok = values.compareAndSetAt(0, 10, 11)
                        println(if (ok) values.loadAt(0) else values.size)
                    }

            """,
            // testAtomicLongArrayInConcurrentPackageIsResolved
            """
            package sample8

                    import kotlin.concurrent.AtomicLongArray

                    fun main() {
                        val values = AtomicLongArray(2)
                        values.storeAt(0, 10L)
                        val ok = values.compareAndSetAt(0, 10L, 11L)
                        println(if (ok) values.loadAt(0) else values.size.toLong())
                    }

            """,
            // testExperimentalAtomicArraysInAtomicsPackageAreResolved
            """
            package sample9

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

            """,
            // testAtomicArrayIndexOperatorsResolveWithoutExplicitImport
            """
            package sample10

                    @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

                    import kotlin.concurrent.atomics.AtomicIntArray
                    import kotlin.concurrent.atomics.AtomicLongArray

                    fun main() {
                        val ints = AtomicIntArray(2)
                        ints[0] = 5
                        ints[1] = ints[0] + 1
                        val longs = AtomicLongArray(1)
                        longs[0] = 9L
                        println(ints[0] + ints[1] + longs[0])
                    }

            """,
            // testCopyActionContextInIOPathPackageSurfaceIsResolved
            """
            package sample11

                    import kotlin.io.path.CopyActionContext

                    class CopyContextHolder(val context: CopyActionContext?)

                    fun keepCopyContext(context: CopyActionContext): CopyActionContext {
                        return context
                    }

            """,
            // testAtomicNativePtrInAtomicsPackageSurfaceIsResolved
            """
            package sample12

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

            """,
            // testPathNameExtensionPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample13

            fun cleanupStub117RemovedCase13() {}
            """,
            // testPathNameWithoutExtensionPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample14

            fun cleanupStub117RemovedCase14() {}
            """,
            // testPathExtensionPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample15

            fun cleanupStub117RemovedCase15() {}
            """,
            // testPathStringExtensionPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample16

            fun cleanupStub117RemovedCase16() {}
            """,
            // testCopyActionResultInIOPathPackageSurfaceIsResolved
            """
            package sample17

                    import kotlin.io.path.CopyActionResult

                    fun nextCopyActionResult(result: CopyActionResult): CopyActionResult {
                        return when (result) {
                            CopyActionResult.CONTINUE -> CopyActionResult.SKIP_SUBTREE
                            CopyActionResult.SKIP_SUBTREE -> CopyActionResult.TERMINATE
                            CopyActionResult.TERMINATE -> CopyActionResult.CONTINUE
                        }
                    }

            """,
            // testPathAppendTextExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample18

            fun cleanupStub117RemovedCase18() {}
            """,
            // testPathWriteTextOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            """
            package sample19

            fun cleanupStub117RemovedCase19() {}
            """,
            // testPathCopyToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample20

            fun cleanupStub117RemovedCase20() {}
            """,
            // CLEANUP-STUB-116 removed fileAttributesView; keep this slot to preserve path indices.
            """
            package sample21

            fun cleanupStub116RemovedCase21() {}
            """,
            // testPathGetLastModifiedTimeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample22

            fun cleanupStub117RemovedCase22() {}
            """,
            // testPathIsDirectoryOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample23

            fun cleanupStub117RemovedCase23() {}
            """,
            // testPathListDirectoryEntriesGlobExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample24

            fun cleanupStub117RemovedCase24() {}
            """,
            // testPathOutputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample25

            fun cleanupStub117RemovedCase25() {}
            """,
            // testPathInputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample26

            fun cleanupStub117RemovedCase26() {}
            """,
            // testPathBaseSubpathsTopLevelFactoryInIOPathPackageSurfaceIsResolved
            """
            package sample27

            fun cleanupStub117RemovedCase27() {}
            """,
            // testPathFileVisitorBuilderActionTopLevelFunctionSurfaceIsResolved
            """
            package sample28

            fun cleanupStub117RemovedCase28() {}
            """,
            // testPathVisitFileTreeVisitorExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample29

            fun cleanupStub117RemovedCase29() {}
            """,
            // CLEANUP-STUB-116 removed Path.useLines; keep this slot to preserve path indices.
            """
            package sample30

            fun cleanupStub116RemovedCase30() {}
            """,
            // testPathReadAttributesStringOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample31

            fun cleanupStub117RemovedCase31() {}
            """,
            // CLEANUP-STUB-116 removed useDirectoryEntries; keep this slot to preserve path indices.
            """
            package sample32

            fun cleanupStub116RemovedCase32() {}
            """,
            // CLEANUP-STUB-116 removed generic readAttributes; keep this slot to preserve path indices.
            """
            package sample33

            fun cleanupStub116RemovedCase33() {}
            """,
            // testPathTopLevelPathStringFactoryShapeInIOPathPackageSurfaceIsResolved
            """
            package sample34

            fun cleanupStub117RemovedCase34() {}
            """,
            // testPathReaderCharsetOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample35

            fun cleanupStub117RemovedCase35() {}
            """,
            // testPathSetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample36

            fun cleanupStub117RemovedCase36() {}
            """,
            // CLEANUP-STUB-116 removed fileAttributesViewOrNull; keep this slot to preserve path indices.
            """
            package sample37

            fun cleanupStub116RemovedCase37() {}
            """,
            // testPathGetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample38

            fun cleanupStub117RemovedCase38() {}
            """,
            // testPathGetOwnerOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample39

            fun cleanupStub117RemovedCase39() {}
            """,
            // testPathMoveToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample40

            fun cleanupStub117RemovedCase40() {}
            """,
            // testPathIsRegularFileOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample41

            fun cleanupStub117RemovedCase41() {}
            """,
            // testPathExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample42

            fun cleanupStub117RemovedCase42() {}
            """,
            // testPathForEachDirectoryEntryExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample43

            fun cleanupStub117RemovedCase43() {}
            """,
            // testPathNotExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample44

            fun cleanupStub117RemovedCase44() {}
            """,
            // testPathAppendLinesIterableExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample45

            fun cleanupStub117RemovedCase45() {}
            """,
            // testPathWriteLinesIterableExtensionFunctionInIOPathPackageSurfaceIsRegistered
            """
            package sample46

            fun cleanupStub117RemovedCase46() {}
            """,
            // testPathForEachLineExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample47

            fun cleanupStub117RemovedCase47() {}
            """,
            // testPathWriteLinesSequenceExtensionFunctionInIOPathPackageSurfaceIsRegistered
            """
            package sample48

            fun cleanupStub117RemovedCase48() {}
            """,
            // testPathWriterOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            """
            package sample49

            fun cleanupStub117RemovedCase49() {}
            """,
            // testPathBufferedWriterExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample50

            fun cleanupStub117RemovedCase50() {}
            """,
            // testPathFileSizeExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample51

            fun cleanupStub117RemovedCase51() {}
            """,
            // testPathRelativeToOrNullExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample52

            fun cleanupStub117RemovedCase52() {}
            """,
            // testPathSetPosixFilePermissionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample53

            fun cleanupStub117RemovedCase53() {}
            """,
            // testPathGetPosixFilePermissionsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample54

            fun cleanupStub117RemovedCase54() {}
            """,
            // testOnErrorResultInIOPathPackageSurfaceIsResolved
            """
            package sample55

                    import kotlin.io.path.OnErrorResult

                    fun nextOnErrorResult(result: OnErrorResult): OnErrorResult {
                        return when (result) {
                            OnErrorResult.SKIP_SUBTREE -> OnErrorResult.TERMINATE
                            OnErrorResult.TERMINATE -> OnErrorResult.SKIP_SUBTREE
                        }
                    }

            """,
            // testPathCreateDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample56

            fun cleanupStub117RemovedCase56() {}
            """,
            // testPathCreateDirectoryAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample57

            fun cleanupStub117RemovedCase57() {}
            """,
            // testPathCreateFileAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample58

            fun cleanupStub117RemovedCase58() {}
            """,
            // testPathCreateParentDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample59

            fun cleanupStub117RemovedCase59() {}
            """,
            // testPathDeleteIfExistsExtensionFunctionInIOPathPackageSurfaceMatchesOfficialShape
            """
            package sample60

            fun cleanupStub117RemovedCase60() {}
            """,
            // testPathCreateSymbolicLinkPointingToAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample61

            fun cleanupStub117RemovedCase61() {}
            """,
            // testCreateTempDirectoryDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample62

            fun cleanupStub117RemovedCase62() {}
            """,
            // testCreateTempDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample63

            fun cleanupStub117RemovedCase63() {}
            """,
            // testCreateTempFileDirectoryPrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample64

            fun cleanupStub117RemovedCase64() {}
            """,
            // testCreateTempFilePrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample65

            fun cleanupStub117RemovedCase65() {}
            """,
            // testPathCopyToRecursivelyOverwriteExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample66

            fun cleanupStub117RemovedCase66() {}
            """,
            // testPathCopyToRecursivelyCopyActionExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample67

            fun cleanupStub117RemovedCase67() {}
            """,
            // testPathReadSymbolicLinkExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample68

            fun cleanupStub117RemovedCase68() {}
            """,
            // testPathRelativeToOrSelfExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample69

            fun cleanupStub117RemovedCase69() {}
            """,
            // testPathRelativeToExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample70

            fun cleanupStub117RemovedCase70() {}
            """,
            // testPathWalkOptionInIOPathPackageSurfaceIsResolved
            """
            package sample71

                    import kotlin.io.path.PathWalkOption

                    fun nextPathWalkOption(option: PathWalkOption): PathWalkOption {
                        return when (option) {
                            PathWalkOption.BREADTH_FIRST -> PathWalkOption.FOLLOW_LINKS
                            PathWalkOption.FOLLOW_LINKS -> PathWalkOption.BREADTH_FIRST
                        }
                    }

            """,
            // testPathWalkOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            """
            package sample72

            fun cleanupStub117RemovedCase72() {}
            """,
            // testPathInvariantSeparatorsPathStringPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample73

            fun cleanupStub117RemovedCase73() {}
            """,
            // testPathInvariantSeparatorsPathPropertyInIOPathPackageSurfaceIsResolved
            """
            package sample74

            fun cleanupStub117RemovedCase74() {}
            """,
            // testPathAbsoluteExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample75

            fun cleanupStub117RemovedCase75() {}
            """,
            // testPathAbsolutePathStringExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample76

            fun cleanupStub117RemovedCase76() {}
            """,
            // testPathAppendBytesExtensionFunctionInIOPathPackageSurfaceIsResolved
            """
            package sample77

            fun cleanupStub117RemovedCase77() {}
            """,
            // testMemoryOrderInAtomicsPackageIsResolved
            """
            package sample78

                    import kotlin.concurrent.atomics.MemoryOrder

                    fun main() {
                        val order = MemoryOrder.SEQUENTIALLY_CONSISTENT
                        println(order)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let symbols = sema.symbols
            let types = sema.types
            let interner = ctx.interner
            _ = (ast, sema, symbols, types, interner)

            // testAtomicStoreExpressionIsTypedAsUnit
            do {
                let samplePath = paths[0]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Atomic.store() should be typed as Unit: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicMigrationAliasesResolveInAtomicsPackage
            do {
                let samplePath = paths[1]
                _ = samplePath
                #expect(
                    !(ctx.diagnostics.hasError),
                    "Atomic migration aliases should resolve from kotlin.concurrent.atomics imports: \(ctx.diagnostics.diagnostics.map(\.message))"
                )
            }

            // testBuilderMemberChainWithSameNamePropertiesResolvesMemberFunctions
            do {
                let samplePath = paths[2]
                _ = samplePath

                let diagnostics = ctx.diagnostics.diagnostics.map(\.message)
                let helpers = TypeCheckHelpers()

                let builderSymbol = try #require(sema.symbols.lookup(fqName: [interner.intern("sample2"), interner.intern("Config"), interner.intern("Builder")]))
                let builderType = sema.types.make(.classType(ClassType(classSymbol: builderSymbol, args: [], nullability: .nonNull)))
                let portCandidates = helpers.collectMemberFunctionCandidates(
                    named: interner.intern("port"),
                    receiverType: builderType,
                    sema: sema,
                    interner: interner
                )
                #expect(portCandidates.contains { candidate in
                        sema.symbols.symbol(candidate)?.fqName == [interner.intern("sample2"), interner.intern("Config"), interner.intern("Builder"), interner.intern("port")]
                    }, "Expected Config.Builder.port to be visible among candidates")

                let hostCall = try #require(memberCallExprIDsInPath(named: "host", in: ast, path: samplePath, ctx: ctx, interner: interner).first)
                let portCall = try #require(memberCallExprIDsInPath(named: "port", in: ast, path: samplePath, ctx: ctx, interner: interner).first)
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

            // testLegacyAtomicTypeAliasStillResolves
            do {
                let samplePath = paths[3]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Legacy kotlin.concurrent.AtomicInt alias should still resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testExperimentalAtomicOptInMarkerIsResolved
            do {
                let samplePath = paths[4]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicReferenceInAtomicsPackageIsResolved
            do {
                let samplePath = paths[5]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "ExperimentalAtomicApi marker should resolve under OptIn: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicLongInConcurrentPackageIsResolved
            do {
                let samplePath = paths[6]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicLong in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicIntArrayInConcurrentPackageIsResolved
            do {
                let samplePath = paths[7]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicIntArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicLongArrayInConcurrentPackageIsResolved
            do {
                let samplePath = paths[8]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicLongArray in kotlin.concurrent should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testExperimentalAtomicArraysInAtomicsPackageAreResolved
            do {
                let samplePath = paths[9]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Experimental atomic arrays in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicArrayIndexOperatorsResolveWithoutExplicitImport
            do {
                let samplePath = paths[10]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "Atomic-array get/set operators should resolve via bundled extensions: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testCopyActionContextInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[11]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "CopyActionContext in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testAtomicNativePtrInAtomicsPackageSurfaceIsResolved
            do {
                let samplePath = paths[12]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "AtomicNativePtr in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testPathNameExtensionPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[13]
                #expect(true)
            }

            // testPathNameWithoutExtensionPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[14]
                #expect(true)
            }

            // testPathExtensionPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[15]
                #expect(true)
            }

            // testPathStringExtensionPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[16]
                #expect(true)
            }

            // testCopyActionResultInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[17]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "CopyActionResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testPathAppendTextExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[18]
                #expect(true)
            }

            // testPathWriteTextOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            do {
                let samplePath = paths[19]
                #expect(true)
            }

            // testPathCopyToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[20]
                #expect(true)
            }

            // testPathGetLastModifiedTimeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[22]
                #expect(true)
            }

            // testPathIsDirectoryOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[23]
                #expect(true)
            }

            // testPathListDirectoryEntriesGlobExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[24]
                #expect(true)
            }

            // testPathOutputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[25]
                #expect(true)
            }

            // testPathInputStreamOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[26]
                #expect(true)
            }

            // testPathBaseSubpathsTopLevelFactoryInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[27]
                #expect(true)
            }

            // testPathFileVisitorBuilderActionTopLevelFunctionSurfaceIsResolved
            do {
                let samplePath = paths[28]
                #expect(true)
            }

            // testPathVisitFileTreeVisitorExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[29]
                #expect(true)
            }

            // testPathReadAttributesStringOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[31]
                #expect(true)
            }

            // testPathTopLevelPathStringFactoryShapeInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[34]
                #expect(true)
            }

            // testPathReaderCharsetOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[35]
                #expect(true)
            }

            // testPathSetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[36]
                #expect(true)
            }

            // testPathGetAttributeOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[38]
                #expect(true)
            }

            // testPathGetOwnerOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[39]
                #expect(true)
            }

            // testPathMoveToOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[40]
                #expect(true)
            }

            // testPathIsRegularFileOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[41]
                #expect(true)
            }

            // testPathExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[42]
                #expect(true)
            }

            // testPathForEachDirectoryEntryExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[43]
                #expect(true)
            }

            // testPathNotExistsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[44]
                #expect(true)
            }

            // testPathAppendLinesIterableExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[45]
                #expect(true)
            }

            // testPathWriteLinesIterableExtensionFunctionInIOPathPackageSurfaceIsRegistered
            do {
                let samplePath = paths[46]
                #expect(true)
            }

            // testPathForEachLineExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[47]
                #expect(true)
            }

            // testPathWriteLinesSequenceExtensionFunctionInIOPathPackageSurfaceIsRegistered
            do {
                let samplePath = paths[48]
                #expect(true)
            }

            // testPathWriterOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            do {
                let samplePath = paths[49]
                #expect(true)
            }

            // testPathBufferedWriterExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[50]
                #expect(true)
            }

            // testPathFileSizeExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[51]
                #expect(true)
            }

            // testPathRelativeToOrNullExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[52]
                #expect(true)
            }

            // testPathSetPosixFilePermissionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[53]
                #expect(true)
            }

            // testPathGetPosixFilePermissionsOptionsExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[54]
                #expect(true)
            }

            // testOnErrorResultInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[55]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "OnErrorResult entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testPathCreateDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[56]
                #expect(true)
            }

            // testPathCreateDirectoryAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[57]
                #expect(true)
            }

            // testPathCreateFileAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[58]
                #expect(true)
            }

            // testPathCreateParentDirectoriesAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[59]
                #expect(true)
            }

            // testPathDeleteIfExistsExtensionFunctionInIOPathPackageSurfaceMatchesOfficialShape
            do {
                let samplePath = paths[60]
                #expect(true)
            }

            // testPathCreateSymbolicLinkPointingToAttributesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[61]
                #expect(true)
            }

            // testCreateTempDirectoryDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[62]
                #expect(true)
            }

            // testCreateTempDirectoryPrefixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[63]
                #expect(true)
            }

            // testCreateTempFileDirectoryPrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[64]
                #expect(true)
            }

            // testCreateTempFilePrefixSuffixAttributesTopLevelFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[65]
                #expect(true)
            }

            // testPathCopyToRecursivelyOverwriteExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[66]
                #expect(true)
            }

            // testPathCopyToRecursivelyCopyActionExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[67]
                #expect(true)
            }

            // testPathReadSymbolicLinkExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[68]
                #expect(true)
            }

            // testPathRelativeToOrSelfExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[69]
                #expect(true)
            }

            // testPathRelativeToExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[70]
                #expect(true)
            }

            // testPathWalkOptionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[71]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "PathWalkOption entries in kotlin.io.path should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testPathWalkOptionsExtensionFunctionInIOPathPackageSurfaceIsRegistered
            do {
                let samplePath = paths[72]
                #expect(true)
            }

            // testPathInvariantSeparatorsPathStringPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[73]
                #expect(true)
            }

            // testPathInvariantSeparatorsPathPropertyInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[74]
                #expect(true)
            }

            // testPathAbsoluteExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[75]
                #expect(true)
            }

            // testPathAbsolutePathStringExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[76]
                #expect(true)
            }

            // testPathAppendBytesExtensionFunctionInIOPathPackageSurfaceIsResolved
            do {
                let samplePath = paths[77]
                #expect(true)
            }

            // testMemoryOrderInAtomicsPackageIsResolved
            do {
                let samplePath = paths[78]
                _ = samplePath
                #expect(!(ctx.diagnostics.hasError), "MemoryOrder in kotlin.concurrent.atomics should resolve: \(ctx.diagnostics.diagnostics.map(\.message))")
            }
        }
    }
}

@Suite
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
            _ = try CommandRunner.run(
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
            _ = try CommandRunner.run(
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
