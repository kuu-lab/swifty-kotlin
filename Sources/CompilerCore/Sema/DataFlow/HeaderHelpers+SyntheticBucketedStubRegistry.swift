import Foundation

// Bucketed synthetic stub registry (RF-STUB-006).
// Entries stay in the historical registration order, but each call is tagged
// with the stdlib-pipeline bucket it belongs to: target-out cleanup (a),
// source-backed migration (b), or compiler/runtime residual (c).

private enum SyntheticStubRegistryBucket: String {
    case targetOutCleanup = "a"
    case sourceBackedMigration = "b"
    case residualCompilerSurface = "c"
}

private struct SyntheticStubRegistryEntry {
    let bucket: SyntheticStubRegistryBucket
    let name: String
    let register: (DataFlowSemaPhase, SymbolTable, TypeSystem, StringInterner) -> Void
}

struct SyntheticDelegateStubRegistryContext {
    let kotlinPkg: [InternedString]
    let kotlinPropertiesPkg: [InternedString]
    let bundledIndex: BundledDeclarationIndex
    let skipStats: SyntheticStubSkipStatsCollector
}

private struct SyntheticDelegateStubRegistryEntry {
    let bucket: SyntheticStubRegistryBucket
    let name: String
    let register: (
        DataFlowSemaPhase,
        SymbolTable,
        TypeSystem,
        StringInterner,
        SyntheticDelegateStubRegistryContext
    ) -> Void
}

private func delegateStubRegistryEntries() -> [SyntheticDelegateStubRegistryEntry] {
    [
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Any") { phase, symbols, types, interner, context in
            phase.registerSyntheticAnyStub(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Number") { phase, symbols, types, interner, context in
            phase.registerSyntheticNumberStub(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "PropertyInterfaces") { phase, symbols, types, interner, context in
            phase.registerSyntheticPropertyInterfaceStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinPkg: context.kotlinPkg,
                kotlinPropertiesPkg: context.kotlinPropertiesPkg
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Random") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRandomStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Collections") { phase, symbols, types, interner, context in
            phase.registerSyntheticCollectionStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KFunctionParametersPatch") { phase, symbols, types, interner, _ in
            phase.patchKFunctionParametersType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KTypeArgumentsPatch") { phase, symbols, types, interner, _ in
            phase.patchKTypeArgumentsType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KTypeParameterUpperBoundsPatch") { phase, symbols, types, interner, _ in
            phase.patchKTypeParameterUpperBoundsType(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "RangeProgression") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRangeProgressionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "RangeUntil") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRangeUntilStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Comparable") { phase, symbols, types, interner, _ in
            if types.comparableInterfaceSymbol == nil {
                phase.registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
            }
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "BuilderDSL") { phase, symbols, types, interner, _ in
            phase.registerSyntheticBuilderDSLStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Comparator") { phase, symbols, types, interner, _ in
            phase.registerSyntheticComparatorStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "ArrayBinarySearchComparatorPatch") { phase, symbols, types, interner, _ in
            phase.patchArrayBinarySearchComparatorStub(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "ArraySortedArrayComparatorPatch") { phase, symbols, types, interner, _ in
            phase.patchArraySortedArrayWithComparatorStub(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Comparison") { phase, symbols, types, interner, _ in
            phase.registerSyntheticComparisonStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "String") { phase, symbols, types, interner, _ in
            phase.registerSyntheticStringStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Char") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCharStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Math") { phase, symbols, types, interner, _ in
            phase.registerSyntheticMathStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "StdlibLoop") { phase, symbols, types, interner, _ in
            phase.registerSyntheticStdlibLoopStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "ScopeFunction") { phase, symbols, types, interner, _ in
            phase.registerSyntheticScopeFunctionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "TestFramework") { phase, symbols, types, interner, context in
            phase.registerSyntheticTestFrameworkStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                kotlinPkg: context.kotlinPkg
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Coroutine") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCoroutineStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Exception") { phase, symbols, types, interner, context in
            phase.registerSyntheticExceptionStubs(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Contract") { phase, symbols, types, interner, _ in
            phase.registerSyntheticContractStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Precondition") { phase, symbols, types, interner, _ in
            phase.registerSyntheticPreconditionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Regex") { phase, symbols, types, interner, _ in
            phase.registerSyntheticRegexStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "KotlinVersion") { phase, symbols, types, interner, _ in
            phase.registerSyntheticKotlinVersionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "DeepRecursive") { phase, symbols, types, interner, _ in
            phase.registerSyntheticDeepRecursiveStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Duration") { phase, symbols, types, interner, _ in
            phase.registerSyntheticDurationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Instant") { phase, symbols, types, interner, _ in
            phase.registerSyntheticInstantStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Clock") { phase, symbols, types, interner, _ in
            phase.registerSyntheticClockStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "ExperimentalTime") { phase, symbols, types, interner, _ in
            phase.registerSyntheticExperimentalTimeStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "PlatformTimeConversion") { phase, symbols, types, interner, _ in
            phase.registerSyntheticPlatformTimeConversionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "StringBuilder") { phase, symbols, types, interner, context in
            let owner = [interner.intern("kotlin"), interner.intern("text"), interner.intern("StringBuilder")]
            if context.bundledIndex.contains(ownerFQName: owner, name: interner.intern("append"), arity: 1) {
                phase.patchSourceBackedStringBuilderSupertypes(symbols: symbols, types: types, interner: interner)
                return
            }
            phase.registerSyntheticStringBuilderStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "JsAny") { phase, symbols, types, interner, _ in
            phase.registerSyntheticJsAnyStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "JsFunction") { phase, symbols, types, interner, _ in
            phase.registerSyntheticJsFunctionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "JsNumber") { phase, symbols, types, interner, _ in
            phase.registerSyntheticJsNumberStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "TODOAndIO") { phase, symbols, types, interner, context in
            phase.registerSyntheticTODOAndIOStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KPropertyFunctionSupertypePatch") { phase, symbols, types, interner, _ in
            phase.patchKPropertyFunctionSupertypes(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty0FunctionSupertypePatch") { phase, symbols, types, interner, _ in
            phase.patchKMutableProperty0FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty1FunctionSupertypePatch") { phase, symbols, types, interner, _ in
            phase.patchKMutableProperty1FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Closeable") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCloseableStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "FileIO") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFileIOStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "KotlinIOException") { phase, symbols, types, interner, _ in
            phase.registerSyntheticKotlinIOExceptionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "FileWalkDirection") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFileWalkDirectionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "FileTreeWalk") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFileTreeWalkStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "OnErrorAction") { phase, symbols, types, interner, _ in
            phase.registerSyntheticOnErrorActionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "FilesUtility") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFilesUtilityStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .targetOutCleanup, name: "Path") { phase, symbols, types, interner, _ in
            phase.registerSyntheticPathStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "LateListIndexedMembers") { phase, symbols, types, interner, context in
            phase.registerLateListIndexedMembers(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                skipStats: context.skipStats
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .sourceBackedMigration, name: "Coercion") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCoercionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExtendedStdlibBuckets") { phase, symbols, types, interner, _ in
            phase.registerSyntheticBucketedExtendedStdlibStubs(symbols: symbols, types: types, interner: interner)
        },
    ]
}

private func extendedStdlibRegistryEntries() -> [SyntheticStubRegistryEntry] {
    [
        SyntheticStubRegistryEntry(bucket: .sourceBackedMigration, name: "ExperimentalBitwise") { phase, symbols, types, interner in
            phase.registerSyntheticExperimentalBitwiseStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "Enum") { phase, symbols, types, interner in
            phase.registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .sourceBackedMigration, name: "Atomic") { phase, symbols, types, interner in
            phase.registerSyntheticAtomicStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .sourceBackedMigration, name: "Uuid") { phase, symbols, types, interner in
            phase.registerSyntheticUuidStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "Serialization") { phase, symbols, types, interner in
            phase.registerSyntheticSerializationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "URI") { phase, symbols, types, interner in
            phase.registerSyntheticURIStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "URL") { phase, symbols, types, interner in
            phase.registerSyntheticURLStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "LocaleConstructor") { phase, symbols, types, interner in
            phase.registerSyntheticLocaleConstructorStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "KotlinAnnotation") { phase, symbols, types, interner in
            phase.registerSyntheticKotlinAnnotationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeInterop") { phase, symbols, types, interner in
            phase.registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "BigInteger") { phase, symbols, types, interner in
            phase.registerSyntheticBigIntegerStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "NativeInvoke") { phase, symbols, _, interner in
            phase.registerSyntheticNativeInvokeStubs(symbols: symbols, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "ThreadLocal") { phase, symbols, types, interner in
            phase.registerSyntheticThreadLocalStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "NativeSetter") { phase, symbols, _, interner in
            phase.registerSyntheticNativeSetterStubs(symbols: symbols, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "Concurrency") { phase, symbols, types, interner in
            phase.registerSyntheticConcurrencyStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineCancellation") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineCancellationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineIntrinsics") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "ReadWriteLock") { phase, symbols, types, interner in
            phase.registerSyntheticReadWriteLockStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeRefRuntime") { phase, symbols, types, interner in
            phase.registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeConcurrent") { phase, symbols, types, interner in
            phase.registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .targetOutCleanup, name: "NativeGetter") { phase, symbols, _, interner in
            phase.registerSyntheticNativeGetterStubs(symbols: symbols, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExperimentalMarker") { phase, symbols, _, interner in
            phase.registerSyntheticExperimentalMarkerStubs(symbols: symbols, interner: interner)
        },
    ]
}

extension DataFlowSemaPhase {
    func registerSyntheticDelegateRegistryStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        context: SyntheticDelegateStubRegistryContext
    ) {
        for entry in delegateStubRegistryEntries() {
            _ = (entry.bucket, entry.name)
            entry.register(self, symbols, types, interner, context)
        }
    }

    func registerSyntheticBucketedExtendedStdlibStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        for entry in extendedStdlibRegistryEntries() {
            _ = (entry.bucket, entry.name)
            entry.register(self, symbols, types, interner)
        }
    }
}
