// Consolidated residual coroutine Sema registry (RF-STUB-005).
// Keeps coroutine package, ABI, and helper registration in one file so similarly
// named residual files do not drift apart.

extension DataFlowSemaPhase {
    func registerSyntheticCoroutineStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex = .empty
    ) {
        var context = SyntheticCoroutineRegistryContext(
            symbols: symbols,
            types: types,
            interner: interner,
            bundledIndex: bundledIndex
        )
        registerCoroutinePackageTree(context: &context)
        registerRestrictsSuspensionResidual(context: &context)
        registerChannelAndFlowPackages(context: &context)
        registerCoreCoroutineTypes(context: &context)
        registerCoroutineNominalTypes(context: &context)
        registerContinuationStubs(context: &context)
        registerFlowCollectMember(context: &context)
        registerSuspendCoroutineUninterceptedOrReturn(context: &context)
        registerCancellationExceptionConstructors(context: &context)
        registerCoroutineLauncherStubs(context: &context)
        registerCoroutineContextHierarchy(context: &context)
        registerCoroutineContextElements(context: &context)
        registerCoroutineBuilderStubs(context: &context)
        registerCoroutineIntrinsicFunctions(context: &context)
        registerCoroutineContextPlusOperators(context: &context)
        registerCoroutineJobChannelStubs(context: &context)
        registerEmptyCoroutineContextStub(context: &context)
        registerCoroutineTestStubs(context: &context)
        registerCoroutineSyncStubs(context: &context)
        registerCoroutineCancellationExtension(context: &context)
    }

}


/// Shared mutable state for `registerSyntheticCoroutineStubs`: the Sema
/// inputs plus the symbol/type handles each extracted registration block
/// hands to later blocks. The extracted methods in the sibling
/// `HeaderHelpers+SyntheticCoroutine*.swift` files read inputs through
/// `let` shadows and write produced handles back here, preserving the
/// original sequential evaluation order exactly.
struct SyntheticCoroutineRegistryContext {
    let symbols: SymbolTable
    let types: TypeSystem
    let interner: StringInterner
    let bundledIndex: BundledDeclarationIndex

    // MARK: Package anchors
    var kotlinPkg: [InternedString] = []
    var kotlinCoroutinesPkg: [InternedString] = []
    var kotlinCoroutinesIntrinsicsPkg: [InternedString] = []
    var cancellationPkg: [InternedString] = []
    var coroutinesPkg: [InternedString] = []
    var kotlinCoroutinesCancellationPkg: [InternedString] = []
    var channelsPkg: [InternedString] = []
    var flowPkg: [InternedString] = []

    // MARK: kotlin.coroutines core types
    var kotlinCoroutineContextSymbol: SymbolID!
    var kotlinCoroutineContextType: TypeID!
    var kotlinResultSymbol: SymbolID!
    var continuationSymbol: SymbolID!
    var continuationTypeParameterSymbol: SymbolID!
    var continuationTType: TypeID!
    var continuationType: TypeID!
    var continuationInterceptorSymbol: SymbolID!
    var continuationInterceptorType: TypeID!
    var continuationFactoryTypeParamSymbol: SymbolID!
    var continuationFactoryTType: TypeID!

    // MARK: kotlinx / nominal types
    var throwableSymbol: SymbolID!
    var throwableType: TypeID!
    var exceptionSymbol: SymbolID!
    var exceptionType: TypeID!
    var coroutineScopeSymbol: SymbolID!
    var coroutineScopeType: TypeID!
    var jobSymbol: SymbolID!
    var jobType: TypeID!
    var deferredSymbol: SymbolID!
    var deferredType: TypeID!
    var flowInterfaceSymbol: SymbolID!
    var flowTypeParamSymbol: SymbolID!
    var flowRawType: TypeID!
    var dispatcherSymbol: SymbolID!
    var dispatcherType: TypeID!
    var channelSymbol: SymbolID!
    var channelType: TypeID!
    var channelIteratorSymbol: SymbolID!
    var channelIteratorType: TypeID!
    var coroutineStartSymbol: SymbolID!
    var coroutineStartType: TypeID!
    var cancellationSymbol: SymbolID!
    var cancellationType: TypeID!
    var cancellationIsSourceBacked = false
    var illegalStateExceptionSymbol: SymbolID?
    var rootCancellationSymbol: SymbolID!
    var rootCancellationType: TypeID!
    var coroutineSuspendedType: TypeID!
    var hasBundledSuspendIntrinsic = false

    // MARK: CoroutineContext hierarchy
    var coroutineContextSymbol: SymbolID!
    var coroutineContextType: TypeID!
    var coroutineContextFQName: [InternedString] = []
    var coroutineContextElementSymbol: SymbolID!
    var coroutineContextKeySymbol: SymbolID!

    // MARK: Context elements
    var coroutineNameSymbol: SymbolID!
    var coroutineNameType: TypeID!
    var hasBundledCoroutineName = false
    var coroutineExceptionHandlerSymbol: SymbolID!
    var coroutineExceptionHandlerType: TypeID!
    var flowBuilderLambdaType: TypeID!
}
