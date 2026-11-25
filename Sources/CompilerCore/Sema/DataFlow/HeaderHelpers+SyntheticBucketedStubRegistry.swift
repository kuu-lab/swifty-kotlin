import Foundation

private enum SyntheticStubRegistryBucket: String {
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
    let projectsCoroutineContextIsActive: Bool
    let isJVMTarget: Bool
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
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "PropertyInterfaces") { phase, symbols, types, interner, context in
            phase.registerSyntheticPropertyInterfaceStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Collections") { phase, symbols, types, interner, context in
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
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Comparable") { phase, symbols, types, interner, _ in
            if types.comparableInterfaceSymbol == nil {
                phase.registerSyntheticComparableStub(symbols: symbols, types: types, interner: interner)
            }
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "String") { phase, symbols, types, interner, context in
            phase.registerSyntheticStringStubs(symbols: symbols, types: types, interner: interner, isJVMTarget: context.isJVMTarget)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Char") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCharStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "PrimitiveCompanionAnchors") { phase, symbols, types, interner, _ in
            phase.registerSyntheticPrimitiveCompanionAnchors(symbols: symbols, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Coroutine") { phase, symbols, types, interner, context in
            phase.registerSyntheticCoroutineStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex,
                projectsCoroutineContextIsActive: context.projectsCoroutineContextIsActive
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Exception") { phase, symbols, types, interner, context in
            phase.registerSyntheticExceptionStubs(symbols: symbols, types: types, interner: interner, kotlinPkg: context.kotlinPkg)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Duration") { phase, symbols, types, interner, _ in
            phase.registerSyntheticDurationStubs(symbols: symbols, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "InstantRuntimeBridges") { phase, symbols, types, interner, _ in
            phase.registerSyntheticInstantStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ClockRuntimeDispatch") { phase, symbols, types, interner, _ in
            phase.registerSyntheticClockStubs(symbols: symbols, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExperimentalTimeAnchors") { phase, symbols, types, interner, context in
            phase.registerSyntheticExperimentalTimeStubs(symbols: symbols, types: types, interner: interner, bundledIndex: context.bundledIndex)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativePlatformFallbacks") { phase, symbols, types, interner, context in
            phase.registerSyntheticNativePlatformStubs(
                symbols: symbols,
                types: types,
                interner: interner,
                bundledIndex: context.bundledIndex
            )
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "FunctionTypes") { phase, symbols, types, interner, _ in
            phase.registerSyntheticFunctionTypes(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KPropertyFunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKPropertyFunctionSupertypes(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty0FunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKMutableProperty0FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "KMutableProperty1FunctionSupertypePatch") { phase, symbols, types, interner, context in
            guard !context.bundledIndex.contains(
                ownerFQName: context.kotlinPkg + [interner.intern("reflect"), interner.intern("KProperty0")],
                name: interner.intern("get"),
                arity: 0
            ) else { return }
            phase.patchKMutableProperty1FunctionSupertype(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "JavaIOStream") { phase, symbols, types, interner, _ in
            phase.registerSyntheticJavaIOStreamStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "Coercion") { phase, symbols, types, interner, _ in
            phase.registerSyntheticCoercionStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticDelegateStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExtendedStdlibBuckets") { phase, symbols, types, interner, _ in
            phase.registerSyntheticBucketedExtendedStdlibStubs(symbols: symbols, types: types, interner: interner)
        },
    ]
}

private func extendedStdlibRegistryEntries() -> [SyntheticStubRegistryEntry] {
    [
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "Enum") { phase, symbols, types, interner in
            phase.registerSyntheticEnumStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "Atomic") { phase, symbols, types, interner in
            phase.registerSyntheticAtomicResidualStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "KotlinAnnotation") { phase, symbols, types, interner in
            phase.registerSyntheticKotlinAnnotationStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeInterop") { phase, symbols, types, interner in
            phase.registerSyntheticNativeInteropStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineCancellation") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineCancellationStubs()
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "CoroutineIntrinsics") { phase, symbols, types, interner in
            phase.registerSyntheticCoroutineIntrinsicsStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeRefRuntime") { phase, symbols, types, interner in
            phase.registerSyntheticNativeRefRuntimeStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "NativeConcurrent") { phase, symbols, types, interner in
            phase.registerSyntheticNativeConcurrentStubs(symbols: symbols, types: types, interner: interner)
        },
        SyntheticStubRegistryEntry(bucket: .residualCompilerSurface, name: "ExperimentalMarker") { phase, symbols, types, interner in
            phase.registerSyntheticExperimentalMarkerStubs(symbols: symbols, types: types, interner: interner)
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
        let stubTrace = ProcessInfo.processInfo.environment["KSWIFTK_DEBUG_STUB_TRACE"] == "1"
        for entry in delegateStubRegistryEntries() {
            _ = (entry.bucket, entry.name)
            if stubTrace {
                FileHandle.standardError.write(Data("STUBENTRY \(entry.name)\n".utf8))
            }
            entry.register(self, symbols, types, interner, context)
        }
        if stubTrace {
            FileHandle.standardError.write(Data("STUBEND delegate\n".utf8))
        }
    }

    func registerSyntheticBucketedExtendedStdlibStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let stubTrace = ProcessInfo.processInfo.environment["KSWIFTK_DEBUG_STUB_TRACE"] == "1"
        for entry in extendedStdlibRegistryEntries() {
            _ = (entry.bucket, entry.name)
            if stubTrace {
                FileHandle.standardError.write(Data("STUBENTRY ext.\(entry.name)\n".utf8))
            }
            entry.register(self, symbols, types, interner)
        }
        if stubTrace {
            FileHandle.standardError.write(Data("STUBENTRY ext.MemoryModelEnumMembers\n".utf8))
        }
        registerSyntheticMemoryModelEnumMembers(
            symbols: symbols,
            types: types,
            interner: interner
        )
        if stubTrace {
            FileHandle.standardError.write(Data("STUBEND ext\n".utf8))
        }
    }
}
