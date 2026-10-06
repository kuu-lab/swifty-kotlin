#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct BundledStdlibOrderingTests {
    @Test
    func testBundledSourcesAreLoadedBeforeUserInputsInDictionaryOrder() throws {
        try withTemporaryFiles(contents: [
            "fun alpha(): Int = 1",
            "fun beta(): Int = 2",
        ]) { paths in
            let ctx = makeCompilationContext(inputs: paths)

            try LoadSourcesPhase().run(ctx)

            let orderedPaths = ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) }
            let bundledEntries = orderedPaths.enumerated()
                .filter { $0.element.hasPrefix("__bundled_") }
            let userEntries = orderedPaths.enumerated()
                .filter { paths.contains($0.element) }

            #expect(!bundledEntries.isEmpty, "Bundled stdlib sources should be injected.")
            #expect(userEntries.count == paths.count)

            let lastBundledOffset = try #require(bundledEntries.map { $0.offset }.max())
            let firstUserOffset = try #require(userEntries.map { $0.offset }.min())
            #expect(lastBundledOffset < firstUserOffset)

            let bundledPaths = bundledEntries.map { $0.element }
            #expect(bundledPaths == bundledPaths.sorted())
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringIndentFormat.kt") })
            #expect(bundledPaths.contains { $0.hasSuffix("kotlin/text/StringSearchReplace.kt") })
        }
    }

    @Test
    func testLexAndParseRecordBundledStdlibSubPhases() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path], frontendFlags: ["time-phases"])
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)

            try LoadSourcesPhase().run(ctx)

            timer.beginPhase(LexPhase.name)
            try LexPhase().run(ctx)
            timer.endPhase()

            timer.beginPhase(ParsePhase.name)
            try ParsePhase().run(ctx)
            timer.endPhase()

            let lexRecord = try #require(timer.phaseRecords.first { $0.name == LexPhase.name })
            let parseRecord = try #require(timer.phaseRecords.first { $0.name == ParsePhase.name })
            #expect(lexRecord.subRecords.contains { $0.name == "bundled-stdlib" })
            #expect(parseRecord.subRecords.contains { $0.name == "bundled-stdlib" })
        }
    }

    @Test
    func testRandomInteropUsesKotlinStdlibPlatformFilename() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let bundledPaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_") }

            #expect(bundledPaths.contains("__bundled_kotlin/random/PlatformRandom.kt"))
            #expect(!bundledPaths.contains("__bundled_kotlin/random/JavaRandomInterop.kt"))
        }
    }

    /// KSP-1541: `kotlin.native` bundled sources use kotlin-native's own
    /// filenames. The two artifact shapes this replaced — a `<Type>/Stdlib.kt`
    /// or `<Type>/<Type>.kt` directory per declaration — have no counterpart
    /// upstream, so neither may come back.
    @Test
    func testNativeBundledFilenamesFollowKotlinNativeLayout() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let nativePaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_kotlin/native/") }

            #expect(!nativePaths.isEmpty, "kotlin.native bundled sources should be injected.")

            for nativePath in nativePaths {
                let components = nativePath.split(separator: "/").map(String.init)
                let file = try #require(components.last)
                #expect(
                    file != "Stdlib.kt",
                    "\(nativePath) still uses the per-declaration Stdlib.kt artifact name."
                )
                if components.count >= 2 {
                    let parent = components[components.count - 2]
                    #expect(
                        file != "\(parent).kt",
                        "\(nativePath) still nests the file inside an eponymous directory."
                    )
                }
            }

            for expected in [
                "__bundled_kotlin/native/Annotations.kt",
                "__bundled_kotlin/native/BitSet.kt",
                "__bundled_kotlin/native/Blob.kt",
                "__bundled_kotlin/native/FreezingIsDeprecated.kt",
                "__bundled_kotlin/native/ObsoleteNativeApi.kt",
                "__bundled_kotlin/native/Platform.kt",
                "__bundled_kotlin/native/Runtime.kt",
                "__bundled_kotlin/native/ThrowableExtensions.kt",
                "__bundled_kotlin/native/simd.kt",
                "__bundled_kotlin/native/concurrent/Atomics.kt",
                "__bundled_kotlin/native/concurrent/Freezing.kt",
                "__bundled_kotlin/native/concurrent/Internal.kt",
                "__bundled_kotlin/native/concurrent/Lazy.kt",
                "__bundled_kotlin/native/concurrent/ObjectTransfer.kt",
                "__bundled_kotlin/native/ref/Cleaner.kt",
                "__bundled_kotlin/native/ref/Weak.kt",
                "__bundled_kotlin/native/ref/WeakPrivate.kt",
                "__bundled_kotlin/native/runtime/GCInfo.kt",
            ] {
                #expect(nativePaths.contains(expected), "Missing bundled source \(expected)")
            }

            // KSP-1541 native residual: `ObjCName`/`CName`/etc. consolidated into
            // Annotations.kt and `ObsoleteNativeApi`/`FreezingIsDeprecated` split into
            // their own files; the old grab-bag filename must not come back.
            #expect(!nativePaths.contains("__bundled_kotlin/native/ObjCInterop.kt"))
        }
    }

    @Test
    func testKotlinxIoFoundationUsesUpstreamFilenames() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try LoadSourcesPhase().run(ctx)
            let paths = Set(ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) })
            for name in ["Annotations.kt", "-Util.kt", "-CommonPlatform.kt", "ByteStrings.kt", "Buffers.kt"] {
                #expect(paths.contains("__bundled_kotlinx/io/\(name)"))
            }
            #expect(!paths.contains("__bundled_kotlinx/io/IOExceptions.kt"))
        }
    }

    /// KSP-1586: Pin the kotlinx resource paths independently of the on-disk
    /// inventory so renames and missing bundled resources cannot pass silently.
    @Test
    func testKotlinxBundledFilenamesAreInjected() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try LoadSourcesPhase().run(ctx)
            let paths = Set(ctx.sourceManager.fileIDs().map { ctx.sourceManager.path(of: $0) })
            for expected in [
                "__bundled_kotlinx/coroutines/AbstractCoroutine.kt",
                "__bundled_kotlinx/coroutines/Annotations.kt",
                "__bundled_kotlinx/coroutines/Await.kt",
                "__bundled_kotlinx/coroutines/Builders.common.kt",
                "__bundled_kotlinx/coroutines/Builders.kt",
                "__bundled_kotlinx/coroutines/CancellableContinuation.kt",
                "__bundled_kotlinx/coroutines/CompletableDeferred.kt",
                "__bundled_kotlinx/coroutines/CompletableJob.kt",
                "__bundled_kotlinx/coroutines/CopyableThrowable.kt",
                "__bundled_kotlinx/coroutines/CoroutineDispatcher.kt",
                "__bundled_kotlinx/coroutines/CoroutineElementKey.kt",
                "__bundled_kotlinx/coroutines/CoroutineId.kt",
                "__bundled_kotlinx/coroutines/CoroutineName.kt",
                "__bundled_kotlinx/coroutines/CoroutineScope.kt",
                "__bundled_kotlinx/coroutines/Deferred.kt",
                "__bundled_kotlinx/coroutines/Delay.kt",
                "__bundled_kotlinx/coroutines/DispatchedTask.kt",
                "__bundled_kotlinx/coroutines/Dispatchers.kt",
                "__bundled_kotlinx/coroutines/Disposables.kt",
                "__bundled_kotlinx/coroutines/Exceptions.kt",
                "__bundled_kotlinx/coroutines/Executors.kt",
                "__bundled_kotlinx/coroutines/Job.kt",
                "__bundled_kotlinx/coroutines/JobSupport.kt",
                "__bundled_kotlinx/coroutines/MainCoroutineDispatcher.kt",
                "__bundled_kotlinx/coroutines/NonCancellable.kt",
                "__bundled_kotlinx/coroutines/Scopes.kt",
                "__bundled_kotlinx/coroutines/ThreadPoolDispatcher.kt",
                "__bundled_kotlinx/coroutines/Timeout.kt",
                "__bundled_kotlinx/coroutines/channels/Actor.kt",
                "__bundled_kotlinx/coroutines/channels/BufferOverflow.kt",
                "__bundled_kotlinx/coroutines/channels/Channel.kt",
                "__bundled_kotlinx/coroutines/channels/ChannelResult.kt",
                "__bundled_kotlinx/coroutines/channels/Channels.kt",
                "__bundled_kotlinx/coroutines/channels/Produce.kt",
                "__bundled_kotlinx/coroutines/flow/Builders.kt",
                "__bundled_kotlinx/coroutines/flow/Channels.kt",
                "__bundled_kotlinx/coroutines/flow/Collect.kt",
                "__bundled_kotlinx/coroutines/flow/Collection.kt",
                "__bundled_kotlinx/coroutines/flow/Count.kt",
                "__bundled_kotlinx/coroutines/flow/Distinct.kt",
                "__bundled_kotlinx/coroutines/flow/Emitters.kt",
                "__bundled_kotlinx/coroutines/flow/Errors.kt",
                "__bundled_kotlinx/coroutines/flow/Flow.kt",
                "__bundled_kotlinx/coroutines/flow/FlowCollector.kt",
                "__bundled_kotlinx/coroutines/flow/Limit.kt",
                "__bundled_kotlinx/coroutines/flow/Logic.kt",
                "__bundled_kotlinx/coroutines/flow/Merge.kt",
                "__bundled_kotlinx/coroutines/flow/Reduce.kt",
                "__bundled_kotlinx/coroutines/flow/Scope.kt",
                "__bundled_kotlinx/coroutines/flow/Share.kt",
                "__bundled_kotlinx/coroutines/flow/SharedFlow.kt",
                "__bundled_kotlinx/coroutines/flow/SharingStarted.kt",
                "__bundled_kotlinx/coroutines/flow/StateFlow.kt",
                "__bundled_kotlinx/coroutines/flow/Transform.kt",
                "__bundled_kotlinx/coroutines/flow/Zip.kt",
                "__bundled_kotlinx/coroutines/internal/Scopes.kt",
                "__bundled_kotlinx/coroutines/selects/Select.kt",
                "__bundled_kotlinx/coroutines/selects/SelectClauses.kt",
                "__bundled_kotlinx/coroutines/sync/Sync.kt",
                "__bundled_kotlinx/coroutines/test/TestBuilders.kt",
                "__bundled_kotlinx/coroutines/test/TestCoroutineScheduler.kt",
                "__bundled_kotlinx/coroutines/test/TestDispatcher.kt",
                "__bundled_kotlinx/coroutines/test/TestScope.kt",
                "__bundled_kotlinx/io/-CommonPlatform.kt",
                "__bundled_kotlinx/io/-Util.kt",
                "__bundled_kotlinx/io/Annotations.kt",
                "__bundled_kotlinx/io/Buffer.kt",
                "__bundled_kotlinx/io/Buffers.kt",
                "__bundled_kotlinx/io/ByteStrings.kt",
                "__bundled_kotlinx/io/Core.kt",
                "__bundled_kotlinx/io/JvmCore.kt",
                "__bundled_kotlinx/io/PeekSource.kt",
                "__bundled_kotlinx/io/RawSink.kt",
                "__bundled_kotlinx/io/RawSource.kt",
                "__bundled_kotlinx/io/RealSink.kt",
                "__bundled_kotlinx/io/RealSource.kt",
                "__bundled_kotlinx/io/Segment.kt",
                "__bundled_kotlinx/io/SegmentPool.kt",
                "__bundled_kotlinx/io/Sink.kt",
                "__bundled_kotlinx/io/Sinks.kt",
                "__bundled_kotlinx/io/SinksJvm.kt",
                "__bundled_kotlinx/io/Source.kt",
                "__bundled_kotlinx/io/Sources.kt",
                "__bundled_kotlinx/io/SourcesJvm.kt",
                "__bundled_kotlinx/io/Utf8.kt",
                "__bundled_kotlinx/io/bytestring/Base64.kt",
                "__bundled_kotlinx/io/bytestring/ByteString.kt",
                "__bundled_kotlinx/io/bytestring/ByteStringBuilder.kt",
                "__bundled_kotlinx/io/bytestring/Hex.kt",
                "__bundled_kotlinx/io/bytestring/unsafe/Annotations.kt",
                "__bundled_kotlinx/io/bytestring/unsafe/UnsafeByteStringOperations.kt",
                "__bundled_kotlinx/io/files/FileNotFoundException.kt",
                "__bundled_kotlinx/io/files/FileSystem.kt",
                "__bundled_kotlinx/io/files/Paths.kt",
                "__bundled_kotlinx/io/internal/-Utf8.kt",
                "__bundled_kotlinx/io/unsafe/UnsafeBufferOperations.kt",
            ] {
                #expect(paths.contains(expected), "Missing bundled source \(expected)")
            }
        }
    }

    /// KSP-1541: packages whose synthetic-stub migration is complete keep the
    /// upstream kotlin-stdlib / kotlin-native file layout. The artifact shapes
    /// this replaced — `<Type>/Stdlib.kt` and `<Type>/<Type>.kt` directories
    /// per declaration — have no counterpart upstream, so neither may come back.
    /// Packages with remaining (b) stubs (`kotlin/` root, collections, ranges,
    /// sequences, text, time, io, concurrent) are covered by their own M-phase
    /// follow-ups and are intentionally not listed here yet.
    @Test
    func testMigratedBundledFilenamesFollowUpstreamLayout() throws {
        try withTemporaryFile(contents: "fun main() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])

            try LoadSourcesPhase().run(ctx)

            let bundledPaths = ctx.sourceManager.fileIDs()
                .map { ctx.sourceManager.path(of: $0) }
                .filter { $0.hasPrefix("__bundled_") }

            let migratedPrefixes = [
                "__bundled_kotlin/annotation/",
                "__bundled_kotlin/contracts/",
                "__bundled_kotlin/coroutines/",
                "__bundled_kotlin/enums/",
                "__bundled_kotlin/experimental/",
                "__bundled_kotlin/reflect/",
            ]
            let migratedPaths = bundledPaths.filter { bundledPath in
                migratedPrefixes.contains { bundledPath.hasPrefix($0) }
            }
            #expect(!migratedPaths.isEmpty, "Migrated bundled sources should be injected.")

            for migratedPath in migratedPaths {
                let components = migratedPath.split(separator: "/").map(String.init)
                let file = try #require(components.last)
                #expect(
                    file != "Stdlib.kt",
                    "\(migratedPath) still uses the per-declaration Stdlib.kt artifact name."
                )
                if components.count >= 2 {
                    let parent = components[components.count - 2]
                    #expect(
                        file != "\(parent).kt",
                        "\(migratedPath) still nests the file inside an eponymous directory."
                    )
                }
            }

            for expected in [
                "__bundled_kotlin/annotation/Annotations.kt",
                "__bundled_kotlin/contracts/ContractBuilder.kt",
                "__bundled_kotlin/contracts/Effect.kt",
                "__bundled_kotlin/contracts/InvocationKind.kt",
                "__bundled_kotlin/coroutines/Continuation.kt",
                "__bundled_kotlin/coroutines/ContinuationInterceptor.kt",
                "__bundled_kotlin/coroutines/CoroutineContext.kt",
                "__bundled_kotlin/coroutines/CoroutineContextImpl.kt",
                "__bundled_kotlin/coroutines/SafeContinuationNative.kt",
                "__bundled_kotlin/coroutines/SuspendFunction.kt",
                "__bundled_kotlin/coroutines/cancellation/CancellationExceptionH.kt",
                "__bundled_kotlin/coroutines/intrinsics/IntrinsicsNative.kt",
                "__bundled_kotlin/enums/EnumEntries.kt",
                "__bundled_kotlin/experimental/ExperimentalNativeApi.kt",
                "__bundled_kotlin/experimental/ExperimentalObjCEnum.kt",
                "__bundled_kotlin/experimental/ExperimentalObjCName.kt",
                "__bundled_kotlin/experimental/ExperimentalObjCRefinement.kt",
                "__bundled_kotlin/experimental/inferenceMarker.kt",
                "__bundled_kotlin/reflect/KCallable.kt",
                "__bundled_kotlin/reflect/KClass.kt",
                "__bundled_kotlin/reflect/KClasses.kt",
                "__bundled_kotlin/reflect/KProperty.kt",
                "__bundled_kotlin/reflect/KType.kt",
                "__bundled_kotlin/reflect/KTypeProjection.kt",
                "__bundled_kotlin/reflect/KVariance.kt",
            ] {
                #expect(bundledPaths.contains(expected), "Missing bundled source \(expected)")
            }
        }
    }
}
#endif
