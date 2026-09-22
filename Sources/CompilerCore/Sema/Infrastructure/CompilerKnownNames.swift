
package enum KnownCompilerAnnotation {
    case deprecated
    case deprecatedSinceKotlin
    case replaceWith
    case metadata
    case requiresOptIn
    case target
    case experimentalStdlibApi
    case experimentalVersionOverloading
    case jvmStatic
    case jvmName
    case jvmField
    case jvmOverloads
    case throws_
    case rootThrows
    case suppress
    case dslMarker
    case parameterName
    case publishedApi
    case wasExperimental
    case sinceKotlin
    case introducedAt
    case optIn
    case subclassOptInRequired
    case consistentCopyVisibility
    case exposedCopyVisibility
    case optionalExpectation
    case builderInference
    case experimentalTypeInference
    case overloadResolutionByLambdaReturnType
    case contextFunctionTypeParams
    case unsafeVariance
    case ksSymbolName

    var simpleName: String {
        switch self {
        case .deprecated:
            "Deprecated"
        case .deprecatedSinceKotlin:
            "DeprecatedSinceKotlin"
        case .replaceWith:
            "ReplaceWith"
        case .metadata:
            "Metadata"
        case .requiresOptIn:
            "RequiresOptIn"
        case .target:
            "Target"
        case .experimentalStdlibApi:
            "ExperimentalStdlibApi"
        case .experimentalVersionOverloading:
            "ExperimentalVersionOverloading"
        case .jvmStatic:
            "JvmStatic"
        case .jvmName:
            "JvmName"
        case .jvmField:
            "JvmField"
        case .jvmOverloads:
            "JvmOverloads"
        case .throws_:
            "Throws"
        case .rootThrows:
            "Throws"
        case .suppress:
            "Suppress"
        case .dslMarker:
            "DslMarker"
        case .parameterName:
            "ParameterName"
        case .publishedApi:
            "PublishedApi"
        case .wasExperimental:
            "WasExperimental"
        case .sinceKotlin:
            "SinceKotlin"
        case .introducedAt:
            "IntroducedAt"
        case .optIn:
            "OptIn"
        case .subclassOptInRequired:
            "SubclassOptInRequired"
        case .consistentCopyVisibility:
            "ConsistentCopyVisibility"
        case .exposedCopyVisibility:
            "ExposedCopyVisibility"
        case .optionalExpectation:
            "OptionalExpectation"
        case .builderInference:
            "BuilderInference"
        case .experimentalTypeInference:
            "ExperimentalTypeInference"
        case .overloadResolutionByLambdaReturnType:
            "OverloadResolutionByLambdaReturnType"
        case .contextFunctionTypeParams:
            "ContextFunctionTypeParams"
        case .unsafeVariance:
            "UnsafeVariance"
        case .ksSymbolName:
            "KsSymbolName"
        }
    }

    var qualifiedName: String {
        switch self {
        case .deprecated:
            "kotlin.Deprecated"
        case .deprecatedSinceKotlin:
            "kotlin.DeprecatedSinceKotlin"
        case .replaceWith:
            "kotlin.ReplaceWith"
        case .metadata:
            "kotlin.Metadata"
        case .requiresOptIn:
            "kotlin.RequiresOptIn"
        case .target:
            "kotlin.annotation.Target"
        case .experimentalStdlibApi:
            "kotlin.ExperimentalStdlibApi"
        case .experimentalVersionOverloading:
            "kotlin.ExperimentalVersionOverloading"
        case .jvmStatic:
            "kotlin.jvm.JvmStatic"
        case .jvmName:
            "kotlin.jvm.JvmName"
        case .jvmField:
            "kotlin.jvm.JvmField"
        case .jvmOverloads:
            "kotlin.jvm.JvmOverloads"
        case .throws_:
            "kotlin.jvm.Throws"
        case .rootThrows:
            "kotlin.Throws"
        case .suppress:
            "kotlin.Suppress"
        case .dslMarker:
            "kotlin.DslMarker"
        case .parameterName:
            "kotlin.ParameterName"
        case .publishedApi:
            "kotlin.PublishedApi"
        case .wasExperimental:
            "kotlin.WasExperimental"
        case .sinceKotlin:
            "kotlin.SinceKotlin"
        case .introducedAt:
            "kotlin.IntroducedAt"
        case .optIn:
            "kotlin.OptIn"
        case .subclassOptInRequired:
            "kotlin.SubclassOptInRequired"
        case .consistentCopyVisibility:
            "kotlin.ConsistentCopyVisibility"
        case .exposedCopyVisibility:
            "kotlin.ExposedCopyVisibility"
        case .optionalExpectation:
            "kotlin.OptionalExpectation"
        case .builderInference:
            "kotlin.BuilderInference"
        case .experimentalTypeInference:
            "kotlin.experimental.ExperimentalTypeInference"
        case .overloadResolutionByLambdaReturnType:
            "kotlin.OverloadResolutionByLambdaReturnType"
        case .contextFunctionTypeParams:
            "kotlin.ContextFunctionTypeParams"
        case .unsafeVariance:
            "kotlin.UnsafeVariance"
        case .ksSymbolName:
            "kotlin.internal.KsSymbolName"
        }
    }

    package func matches(_ rawName: String) -> Bool {
        rawName == simpleName || rawName == qualifiedName
    }
}

enum KnownCollectionKind {
    case list
    case set
    case map
    case collection
    case array
    case sequence
}

package struct KnownCompilerNames {

    let byte: InternedString
    let short: InternedString
    let int: InternedString
    let long: InternedString
    let float: InternedString
    let double: InternedString
    let boolean: InternedString
    let char: InternedString
    let string: InternedString
    let uint: InternedString
    let ulong: InternedString
    let ubyte: InternedString
    let ushort: InternedString
    let any: InternedString
    let unit: InternedString
    let nothing: InternedString

    let map: InternedString
    let mutableMap: InternedString
    let list: InternedString
    let mutableList: InternedString
    let set: InternedString
    let mutableSet: InternedString
    let hashSet: InternedString
    let linkedHashSet: InternedString
    let collection: InternedString
    let mutableCollection: InternedString
    let array: InternedString
    let intArray: InternedString
    let longArray: InternedString
    let shortArray: InternedString
    let byteArray: InternedString
    let ubyteArray: InternedString
    let ushortArray: InternedString
    let ulongArray: InternedString
    let doubleArray: InternedString
    let floatArray: InternedString
    let booleanArray: InternedString
    let charArray: InternedString
    let uintArray: InternedString

    // Range/Progression class names in kotlin.ranges (for-loop lowering)
    let intRange: InternedString
    let longRange: InternedString
    let charRange: InternedString
    let uintRange: InternedString
    let ulongRange: InternedString
    let intProgression: InternedString
    let longProgression: InternedString
    let charProgression: InternedString
    let uintProgression: InternedString
    let ulongProgression: InternedString

    let regex: InternedString
    let stringBuilder: InternedString
    let sequence: InternedString
    let continuation: InternedString
    let suspendCoroutine: InternedString
    let resume: InternedString
    let resumeWith: InternedString
    let resumeWithException: InternedString
    let channel: InternedString
    let job: InternedString
    let deferred: InternedString
    let dispatchers: InternedString
    let charsets: InternedString
    let throwable: InternedString
    let exception: InternedString
    let cancellationException: InternedString

    let null: InternedString
    let field: InternedString
    let thisName: InternedString
    package let main: InternedString
    let with: InternedString
    let run: InternedString
    let withContext: InternedString
    let withTimeout: InternedString
    let withTimeoutOrNull: InternedString
    let suspendCoroutineUninterceptedOrReturn: InternedString
    let flow: InternedString
    let emit: InternedString
    let notNull: InternedString
    let emptyListFn: InternedString
    let emptySetFn: InternedString
    let emptyMapFn: InternedString
    let buildList: InternedString
    let buildSet: InternedString
    let buildMap: InternedString
    let className: InternedString
    let isInitialized: InternedString
    // STDLIB-REFLECT-061: KClass member access (remains a compiler special
    // case — see the NOTE in KClasses.kt)
    let propertiesName: InternedString
    // STDLIB-REFLECT-065: Annotation reflection (reified-type special cases
    // that were not migrated to bundled Kotlin — see KClasses.kt)
    let findAnnotationName: InternedString
    let findAssociatedObjectName: InternedString
    let size: InternedString
    let isEmpty: InternedString
    let getValue: InternedString
    let getOrDefault: InternedString
    let getOrElse: InternedString
    let getOrPut: InternedString
    let putAll: InternedString
    let regexCtor: InternedString
    let runBlocking: InternedString
    let launch: InternedString
    let async: InternedString
    let produce: InternedString

    // Scope function names (STDLIB-004 / STDLIB-250)

    // StringBuilder member names
    let append: InternedString
    let appendLine: InternedString
    let appendRange: InternedString
    let deleteCharAt: InternedString
    let deleteAt: InternedString
    let deleteRange: InternedString
    let get: InternedString
    let sbSet: InternedString
    let insert: InternedString
    let insertRange: InternedString
    let delete: InternedString
    let setRange: InternedString
    let toString: InternedString
    let clear: InternedString
    let reverse: InternedString
    let length: InternedString
    // STDLIB-STR-123
    let replace: InternedString
    let setCharAt: InternedString
    let capacity: InternedString
    let ensureCapacity: InternedString
    let trimToSize: InternedString

    // Member, type, and package names checked on hot member-call paths
    // (collection fallback, regular resolution, KIR lowering dispatch),
    // interned once per interner so call sites compare `InternedString`
    // IDs instead of re-interning literals or resolving back to String.
    let add: InternedString
    let addAll: InternedString
    let asIterable: InternedString
    let asReversed: InternedString
    let asSequence: InternedString
    let average: InternedString
    let binarySearch: InternedString
    let binarySearchBy: InternedString
    let chunked: InternedString
    let coerceIn: InternedString
    let compareTo: InternedString
    let contains: InternedString
    let containsAll: InternedString
    let containsKey: InternedString
    let containsValue: InternedString
    let count: InternedString
    let distinct: InternedString
    let distinctBy: InternedString
    let drop: InternedString
    let eachCount: InternedString
    let elementAt: InternedString
    let elementAtOrElse: InternedString
    let elementAtOrNull: InternedString
    let equals: InternedString
    let filter: InternedString
    let filterIndexed: InternedString
    let filterIsInstance: InternedString
    let filterIsInstanceTo: InternedString
    let filterNot: InternedString
    let filterNotNull: InternedString
    let filterNotNullTo: InternedString
    let find: InternedString
    let first: InternedString
    let firstNotNullOf: InternedString
    let firstNotNullOfOrNull: InternedString
    let firstOrNull: InternedString
    let flatMapIndexed: InternedString
    let flatten: InternedString
    let fold: InternedString
    let foldIndexed: InternedString
    let foldRight: InternedString
    let foldRightIndexed: InternedString
    let forEach: InternedString
    let format: InternedString
    let getOrNull: InternedString
    let hashCode: InternedString
    let indexOf: InternedString
    let indexOfFirst: InternedString
    let indexOfLast: InternedString
    let intersect: InternedString
    let isNullOrEmpty: InternedString
    let iterator: InternedString
    let joinToString: InternedString
    let last: InternedString
    let lastIndexOf: InternedString
    let lastOrNull: InternedString
    let mapIndexed: InternedString
    let mapNotNull: InternedString
    let maxBy: InternedString
    let maxByOrNull: InternedString
    let maxOf: InternedString
    let maxOfOrNull: InternedString
    let maxOfWith: InternedString
    let maxOfWithOrNull: InternedString
    let maxOrNull: InternedString
    let maxWith: InternedString
    let maxWithOrNull: InternedString
    let min: InternedString
    let minBy: InternedString
    let minByOrNull: InternedString
    let minOf: InternedString
    let minOfOrNull: InternedString
    let minOfWith: InternedString
    let minOfWithOrNull: InternedString
    let minOrNull: InternedString
    let minWith: InternedString
    let minWithOrNull: InternedString
    let minus: InternedString
    let minusElement: InternedString
    let partition: InternedString
    let plus: InternedString
    let random: InternedString
    let randomOrNull: InternedString
    let reduce: InternedString
    let reduceIndexed: InternedString
    let reduceIndexedOrNull: InternedString
    let reduceOrNull: InternedString
    let reduceRight: InternedString
    let reduceRightIndexed: InternedString
    let reduceRightIndexedOrNull: InternedString
    let reduceRightOrNull: InternedString
    let reduceTo: InternedString
    let remove: InternedString
    let removeAll: InternedString
    let requireNoNulls: InternedString
    let retainAll: InternedString
    let reversed: InternedString
    let runningFold: InternedString
    let runningFoldIndexed: InternedString
    let runningReduce: InternedString
    let runningReduceIndexed: InternedString
    let scan: InternedString
    let scanIndexed: InternedString
    let scanReduce: InternedString
    let shuffled: InternedString
    let single: InternedString
    let singleOrNull: InternedString
    let slice: InternedString
    let sort: InternedString
    let sortBy: InternedString
    let sortByDescending: InternedString
    let sorted: InternedString
    let sortedBy: InternedString
    let sortedByDescending: InternedString
    let sortedDescending: InternedString
    let sortedWith: InternedString
    let step: InternedString
    let subList: InternedString
    let subtract: InternedString
    let sum: InternedString
    let sumBy: InternedString
    let sumByDouble: InternedString
    let sumOf: InternedString
    let take: InternedString
    let toBooleanArray: InternedString
    let toByteArray: InternedString
    let toCharArray: InternedString
    let toCollection: InternedString
    let toDoubleArray: InternedString
    let toFloatArray: InternedString
    let toIntArray: InternedString
    let toList: InternedString
    let toLongArray: InternedString
    let toMutableList: InternedString
    let toShortArray: InternedString
    let toTypedArray: InternedString
    let toUByteArray: InternedString
    let toUIntArray: InternedString
    let toULongArray: InternedString
    let toUShortArray: InternedString
    let trimMargin: InternedString
    let typeOf: InternedString
    let union: InternedString
    let unzip: InternedString
    let windowed: InternedString
    let withDefault: InternedString
    let withIndex: InternedString
    let zip: InternedString
    let zipWithNext: InternedString
    let pair: InternedString
    let iterable: InternedString
    let comparator: InternedString
    let sequenceScope: InternedString
    let closedFloatingPointRange: InternedString
    let kotlin: InternedString
    let sequences: InternedString
    let initName: InternedString
    let invoke: InternedString
    let yield: InternedString
    let yieldAll: InternedString
    let comparisons: InternedString

    // Package prefixes and FQ names for the same hot paths.
    let kotlinCollectionsPackage: [InternedString]
    let kotlinSequencesPackage: [InternedString]
    let kotlinRangesPackage: [InternedString]
    let kotlinTextPackage: [InternedString]
    let kotlinTimePackage: [InternedString]
    let kotlinMathPackage: [InternedString]
    let kotlinArrayFQName: [InternedString]
    let kotlinPairFQName: [InternedString]
    let kotlinComparatorFQName: [InternedString]
    let kotlinIntArrayFQName: [InternedString]
    let kotlinLongArrayFQName: [InternedString]
    let kotlinShortArrayFQName: [InternedString]
    let kotlinByteArrayFQName: [InternedString]
    let kotlinUByteArrayFQName: [InternedString]
    let kotlinUShortArrayFQName: [InternedString]
    let kotlinUIntArrayFQName: [InternedString]
    let kotlinULongArrayFQName: [InternedString]
    let kotlinDoubleArrayFQName: [InternedString]
    let kotlinFloatArrayFQName: [InternedString]
    let kotlinBooleanArrayFQName: [InternedString]
    let kotlinCharArrayFQName: [InternedString]
    let kotlinCollectionsMutableIterableFQName: [InternedString]
    let kotlinCollectionsIndexedValueFQName: [InternedString]
    let kotlinCollectionsIteratorFQName: [InternedString]
    let kotlinCollectionsMutableIteratorFQName: [InternedString]
    let kotlinCollectionsMapEntryFQName: [InternedString]
    let kotlinRangesCharRangeFQName: [InternedString]
    let kotlinRangesClosedFloatingPointRangeFQName: [InternedString]
    let kotlinTimeInstantFQName: [InternedString]

    // Constant member-name sets for the collection-member fallback and
    // regular-resolution dispatch, interned once per interner instead of
    // rebuilt per call.
    let collectionMembers: Set<InternedString>
    let listOnlyMembers: Set<InternedString>
    let collectionSpecificMembers: Set<InternedString>
    let mutableListOnlyMembers: Set<InternedString>
    let mutableCollectionMembers: Set<InternedString>
    let mapOnlyMembers: Set<InternedString>
    let collectionReturningMembers: Set<InternedString>
    let intReturningMembers: Set<InternedString>
    let boolReturningMembers: Set<InternedString>
    let destinationCollectionReturningMembers: Set<InternedString>
    let listPreservingMembers: Set<InternedString>
    let boolOneParamMembers: Set<InternedString>
    let oneParamMembers: Set<InternedString>
    let setReturningCollectionBinaryMembers: Set<InternedString>
    let bundledRangeSourceMemberNames: Set<InternedString>
    let rangeMigrationMemberNames: Set<InternedString>
    let progressionFirstLastMemberNames: Set<InternedString>
    let instantValueSemanticsMemberNames: Set<InternedString>

    let kotlinRegexFQName: [InternedString]
    let kotlinStringBuilderFQName: [InternedString]
    let kotlinSequenceFQName: [InternedString]
    let kotlinContinuationFQName: [InternedString]
    let kotlinSuspendCoroutineFQName: [InternedString]
    let kotlinCollectionsArrayListFQName: [InternedString]
    let kotlinCollectionsListFQName: [InternedString]
    let kotlinCollectionsMutableListFQName: [InternedString]
    let kotlinCollectionsSetFQName: [InternedString]
    let kotlinCollectionsMutableSetFQName: [InternedString]
    let kotlinCollectionsHashSetFQName: [InternedString]
    let kotlinCollectionsLinkedHashSetFQName: [InternedString]
    let kotlinCollectionsMapFQName: [InternedString]
    let kotlinCollectionsMutableMapFQName: [InternedString]
    let kotlinCollectionsHashMapFQName: [InternedString]
    let kotlinCollectionsLinkedHashMapFQName: [InternedString]
    let kotlinCollectionsCollectionFQName: [InternedString]
    let kotlinCollectionsMutableCollectionFQName: [InternedString]
    let kotlinCollectionsIterableFQName: [InternedString]
    let kotlinEnumsEnumEntriesFQName: [InternedString]
    let kotlinCoroutinesFQName: [InternedString]
    let kotlinCoroutinesIntrinsicsFQName: [InternedString]
    let kotlinxCoroutinesJobFQName: [InternedString]
    let kotlinxCoroutinesDeferredFQName: [InternedString]
    let kotlinxCoroutinesChannelFQName: [InternedString]
    let kotlinxCoroutinesProduceFQName: [InternedString]
    let kotlinxCoroutinesRunBlockingFQName: [InternedString]
    let kotlinxCoroutinesLaunchFQName: [InternedString]
    let kotlinxCoroutinesAsyncFQName: [InternedString]
    let kotlinCoroutinesContinuationFQName: [InternedString]
    let kotlinCoroutinesSuspendCoroutineUninterceptedOrReturnFQName: [InternedString]
    let kotlinRangesPackageFQName: [InternedString]
    let kotlinResultFQName: [InternedString]
    /// Bundled Kotlin-source Array copy entry points (KSP-1515).
    let sourceBackedArrayCopyFQNames: Set<[InternedString]>
    let atomicScalarFactoryFQNames: Set<[InternedString]>

    package init(interner: StringInterner) {
        self = interner.cachedCompilerNames {
            Self(uncachedInterner: interner)
        }
    }

    private init(uncachedInterner interner: StringInterner) {
        byte = interner.intern("Byte")
        short = interner.intern("Short")
        int = interner.intern("Int")
        long = interner.intern("Long")
        float = interner.intern("Float")
        double = interner.intern("Double")
        boolean = interner.intern("Boolean")
        char = interner.intern("Char")
        string = interner.intern("String")
        uint = interner.intern("UInt")
        ulong = interner.intern("ULong")
        ubyte = interner.intern("UByte")
        ushort = interner.intern("UShort")
        any = interner.intern("Any")
        unit = interner.intern("Unit")
        nothing = interner.intern("Nothing")

        map = interner.intern("Map")
        mutableMap = interner.intern("MutableMap")
        list = interner.intern("List")
        mutableList = interner.intern("MutableList")
        set = interner.intern("Set")
        mutableSet = interner.intern("MutableSet")
        hashSet = interner.intern("HashSet")
        linkedHashSet = interner.intern("LinkedHashSet")
        collection = interner.intern("Collection")
        mutableCollection = interner.intern("MutableCollection")
        array = interner.intern("Array")
        intArray = interner.intern("IntArray")
        longArray = interner.intern("LongArray")
        shortArray = interner.intern("ShortArray")
        byteArray = interner.intern("ByteArray")
        ubyteArray = interner.intern("UByteArray")
        ushortArray = interner.intern("UShortArray")
        ulongArray = interner.intern("ULongArray")
        doubleArray = interner.intern("DoubleArray")
        floatArray = interner.intern("FloatArray")
        booleanArray = interner.intern("BooleanArray")
        charArray = interner.intern("CharArray")
        uintArray = interner.intern("UIntArray")

        intRange = interner.intern("IntRange")
        longRange = interner.intern("LongRange")
        charRange = interner.intern("CharRange")
        uintRange = interner.intern("UIntRange")
        ulongRange = interner.intern("ULongRange")
        intProgression = interner.intern("IntProgression")
        longProgression = interner.intern("LongProgression")
        charProgression = interner.intern("CharProgression")
        uintProgression = interner.intern("UIntProgression")
        ulongProgression = interner.intern("ULongProgression")

        regex = interner.intern("Regex")
        stringBuilder = interner.intern("StringBuilder")
        sequence = interner.intern("Sequence")
        continuation = interner.intern("Continuation")
        suspendCoroutine = interner.intern("suspendCoroutine")
        resume = interner.intern("resume")
        resumeWith = interner.intern("resumeWith")
        resumeWithException = interner.intern("resumeWithException")
        channel = interner.intern("Channel")
        job = interner.intern("Job")
        deferred = interner.intern("Deferred")
        dispatchers = interner.intern("Dispatchers")
        charsets = interner.intern("Charsets")
        throwable = interner.intern("Throwable")
        exception = interner.intern("Exception")
        cancellationException = interner.intern("CancellationException")

        null = interner.intern("null")
        field = interner.intern("field")
        thisName = interner.intern("this")
        main = interner.intern("main")
        with = interner.intern("with")
        run = interner.intern("run")
        withContext = interner.intern("withContext")
        withTimeout = interner.intern("withTimeout")
        withTimeoutOrNull = interner.intern("withTimeoutOrNull")
        suspendCoroutineUninterceptedOrReturn = interner.intern("suspendCoroutineUninterceptedOrReturn")
        flow = interner.intern("flow")
        emit = interner.intern("emit")
        notNull = interner.intern("notNull")
        emptyListFn = interner.intern("emptyList")
        emptySetFn = interner.intern("emptySet")
        emptyMapFn = interner.intern("emptyMap")
        buildList = interner.intern("buildList")
        buildSet = interner.intern("buildSet")
        buildMap = interner.intern("buildMap")
        className = interner.intern("class")
        isInitialized = interner.intern("isInitialized")
        propertiesName = interner.intern("properties")
        findAnnotationName = interner.intern("findAnnotation")
        findAssociatedObjectName = interner.intern("findAssociatedObject")
        size = interner.intern("size")
        isEmpty = interner.intern("isEmpty")
        getValue = interner.intern("getValue")
        getOrDefault = interner.intern("getOrDefault")
        getOrElse = interner.intern("getOrElse")
        getOrPut = interner.intern("getOrPut")
        putAll = interner.intern("putAll")
        regexCtor = interner.intern("Regex")
        runBlocking = interner.intern("runBlocking")
        launch = interner.intern("launch")
        async = interner.intern("async")
        produce = interner.intern("produce")

        // Scope function names (STDLIB-004 / STDLIB-250)

        // StringBuilder member names
        append = interner.intern("append")
        appendLine = interner.intern("appendLine")
        appendRange = interner.intern("appendRange")
        deleteCharAt = interner.intern("deleteCharAt")
        deleteAt = interner.intern("deleteAt")
        deleteRange = interner.intern("deleteRange")
        get = interner.intern("get")
        sbSet = interner.intern("set")
        insert = interner.intern("insert")
        insertRange = interner.intern("insertRange")
        delete = interner.intern("delete")
        setRange = interner.intern("setRange")
        toString = interner.intern("toString")
        clear = interner.intern("clear")
        reverse = interner.intern("reverse")
        length = interner.intern("length")
        // STDLIB-STR-123
        replace = interner.intern("replace")
        setCharAt = interner.intern("setCharAt")
        capacity = interner.intern("capacity")
        ensureCapacity = interner.intern("ensureCapacity")
        trimToSize = interner.intern("trimToSize")

        let kotlin = interner.intern("kotlin")
        let kotlinCoroutines = interner.intern("coroutines")
        let kotlinText = interner.intern("text")
        let kotlinCollections = interner.intern("collections")
        let kotlinSequences = interner.intern("sequences")
        let kotlinx = interner.intern("kotlinx")
        let coroutines = interner.intern("coroutines")
        let channels = interner.intern("channels")
        let coroutinesIntrinsics = interner.intern("intrinsics")

        kotlinRegexFQName = [kotlin, kotlinText, regex]
        kotlinStringBuilderFQName = [kotlin, kotlinText, stringBuilder]
        kotlinSequenceFQName = [kotlin, kotlinSequences, sequence]
        kotlinContinuationFQName = [kotlin, kotlinCoroutines, continuation]
        kotlinSuspendCoroutineFQName = [kotlin, kotlinCoroutines, suspendCoroutine]
        kotlinCollectionsArrayListFQName = [kotlin, kotlinCollections, interner.intern("ArrayList")]
        kotlinCollectionsListFQName = [kotlin, kotlinCollections, list]
        kotlinCollectionsMutableListFQName = [kotlin, kotlinCollections, mutableList]
        kotlinCollectionsSetFQName = [kotlin, kotlinCollections, set]
        kotlinCollectionsMutableSetFQName = [kotlin, kotlinCollections, mutableSet]
        kotlinCollectionsHashSetFQName = [kotlin, kotlinCollections, hashSet]
        kotlinCollectionsLinkedHashSetFQName = [kotlin, kotlinCollections, linkedHashSet]
        kotlinCollectionsMapFQName = [kotlin, kotlinCollections, map]
        kotlinCollectionsMutableMapFQName = [kotlin, kotlinCollections, mutableMap]
        kotlinCollectionsHashMapFQName = [kotlin, kotlinCollections, interner.intern("HashMap")]
        kotlinCollectionsLinkedHashMapFQName = [kotlin, kotlinCollections, interner.intern("LinkedHashMap")]
        kotlinCollectionsCollectionFQName = [kotlin, kotlinCollections, collection]
        kotlinCollectionsMutableCollectionFQName = [kotlin, kotlinCollections, mutableCollection]
        kotlinCollectionsIterableFQName = [kotlin, kotlinCollections, interner.intern("Iterable")]
        sourceBackedArrayCopyFQNames = [
            [kotlin, kotlinCollections, interner.intern("copyOf")],
            [kotlin, kotlinCollections, interner.intern("copyOfRange")],
        ]
        kotlinEnumsEnumEntriesFQName = [kotlin, interner.intern("enums"), interner.intern("EnumEntries")]
        kotlinxCoroutinesJobFQName = [kotlinx, coroutines, job]
        kotlinxCoroutinesDeferredFQName = [kotlinx, coroutines, deferred]
        kotlinxCoroutinesChannelFQName = [kotlinx, coroutines, channels, channel]
        kotlinxCoroutinesProduceFQName = [kotlinx, coroutines, channels, produce]
        kotlinxCoroutinesRunBlockingFQName = [kotlinx, coroutines, runBlocking]
        kotlinxCoroutinesLaunchFQName = [kotlinx, coroutines, launch]
        kotlinxCoroutinesAsyncFQName = [kotlinx, coroutines, async]
        kotlinRangesPackageFQName = [kotlin, interner.intern("ranges")]
        kotlinCoroutinesFQName = [kotlin, coroutines]
        kotlinCoroutinesIntrinsicsFQName = [kotlin, coroutines, coroutinesIntrinsics]
        kotlinCoroutinesContinuationFQName = [kotlin, coroutines, continuation]
        kotlinCoroutinesSuspendCoroutineUninterceptedOrReturnFQName = [kotlin, coroutines, coroutinesIntrinsics, suspendCoroutineUninterceptedOrReturn]

        let resultName = interner.intern("Result")
        kotlinResultFQName = [kotlin, resultName]

        let kotlinConcurrent = interner.intern("concurrent")
        let kotlinConcurrentAtomics = interner.intern("atomics")
        let atomicIntName = interner.intern("AtomicInt")
        let atomicLongName = interner.intern("AtomicLong")
        let atomicBooleanName = interner.intern("AtomicBoolean")
        let atomicReferenceName = interner.intern("AtomicReference")
        let atomicIntArrayName = interner.intern("AtomicIntArray")
        let atomicLongArrayName = interner.intern("AtomicLongArray")
        let atomicArrayName = interner.intern("AtomicArray")
        let javaAtomicIntegerName = interner.intern("AtomicInteger")
        let java = interner.intern("java")
        let util = interner.intern("util")
        let javaConcurrent = interner.intern("concurrent")
        let javaAtomic = interner.intern("atomic")
        atomicScalarFactoryFQNames = [
            [kotlin, kotlinConcurrent, atomicIntName],
            [kotlin, kotlinConcurrent, atomicLongName],
            [kotlin, kotlinConcurrent, atomicBooleanName],
            [kotlin, kotlinConcurrent, atomicReferenceName],
            [kotlin, kotlinConcurrent, atomicIntArrayName],
            [kotlin, kotlinConcurrent, atomicLongArrayName],
            [kotlin, kotlinConcurrent, atomicArrayName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicIntName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicLongName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicBooleanName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicReferenceName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicIntArrayName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicLongArrayName],
            [kotlin, kotlinConcurrent, kotlinConcurrentAtomics, atomicArrayName],
            [java, util, javaConcurrent, javaAtomic, javaAtomicIntegerName],
        ]


        add = interner.intern("add")
        addAll = interner.intern("addAll")
        asIterable = interner.intern("asIterable")
        asReversed = interner.intern("asReversed")
        asSequence = interner.intern("asSequence")
        average = interner.intern("average")
        binarySearch = interner.intern("binarySearch")
        binarySearchBy = interner.intern("binarySearchBy")
        chunked = interner.intern("chunked")
        coerceIn = interner.intern("coerceIn")
        compareTo = interner.intern("compareTo")
        contains = interner.intern("contains")
        containsAll = interner.intern("containsAll")
        containsKey = interner.intern("containsKey")
        containsValue = interner.intern("containsValue")
        count = interner.intern("count")
        distinct = interner.intern("distinct")
        distinctBy = interner.intern("distinctBy")
        drop = interner.intern("drop")
        eachCount = interner.intern("eachCount")
        elementAt = interner.intern("elementAt")
        elementAtOrElse = interner.intern("elementAtOrElse")
        elementAtOrNull = interner.intern("elementAtOrNull")
        equals = interner.intern("equals")
        filter = interner.intern("filter")
        filterIndexed = interner.intern("filterIndexed")
        filterIsInstance = interner.intern("filterIsInstance")
        filterIsInstanceTo = interner.intern("filterIsInstanceTo")
        filterNot = interner.intern("filterNot")
        filterNotNull = interner.intern("filterNotNull")
        filterNotNullTo = interner.intern("filterNotNullTo")
        find = interner.intern("find")
        first = interner.intern("first")
        firstNotNullOf = interner.intern("firstNotNullOf")
        firstNotNullOfOrNull = interner.intern("firstNotNullOfOrNull")
        firstOrNull = interner.intern("firstOrNull")
        flatMapIndexed = interner.intern("flatMapIndexed")
        flatten = interner.intern("flatten")
        fold = interner.intern("fold")
        foldIndexed = interner.intern("foldIndexed")
        foldRight = interner.intern("foldRight")
        foldRightIndexed = interner.intern("foldRightIndexed")
        forEach = interner.intern("forEach")
        format = interner.intern("format")
        getOrNull = interner.intern("getOrNull")
        hashCode = interner.intern("hashCode")
        indexOf = interner.intern("indexOf")
        indexOfFirst = interner.intern("indexOfFirst")
        indexOfLast = interner.intern("indexOfLast")
        intersect = interner.intern("intersect")
        isNullOrEmpty = interner.intern("isNullOrEmpty")
        iterator = interner.intern("iterator")
        joinToString = interner.intern("joinToString")
        last = interner.intern("last")
        lastIndexOf = interner.intern("lastIndexOf")
        lastOrNull = interner.intern("lastOrNull")
        mapIndexed = interner.intern("mapIndexed")
        mapNotNull = interner.intern("mapNotNull")
        maxBy = interner.intern("maxBy")
        maxByOrNull = interner.intern("maxByOrNull")
        maxOf = interner.intern("maxOf")
        maxOfOrNull = interner.intern("maxOfOrNull")
        maxOfWith = interner.intern("maxOfWith")
        maxOfWithOrNull = interner.intern("maxOfWithOrNull")
        maxOrNull = interner.intern("maxOrNull")
        maxWith = interner.intern("maxWith")
        maxWithOrNull = interner.intern("maxWithOrNull")
        min = interner.intern("min")
        minBy = interner.intern("minBy")
        minByOrNull = interner.intern("minByOrNull")
        minOf = interner.intern("minOf")
        minOfOrNull = interner.intern("minOfOrNull")
        minOfWith = interner.intern("minOfWith")
        minOfWithOrNull = interner.intern("minOfWithOrNull")
        minOrNull = interner.intern("minOrNull")
        minWith = interner.intern("minWith")
        minWithOrNull = interner.intern("minWithOrNull")
        minus = interner.intern("minus")
        minusElement = interner.intern("minusElement")
        partition = interner.intern("partition")
        plus = interner.intern("plus")
        random = interner.intern("random")
        randomOrNull = interner.intern("randomOrNull")
        reduce = interner.intern("reduce")
        reduceIndexed = interner.intern("reduceIndexed")
        reduceIndexedOrNull = interner.intern("reduceIndexedOrNull")
        reduceOrNull = interner.intern("reduceOrNull")
        reduceRight = interner.intern("reduceRight")
        reduceRightIndexed = interner.intern("reduceRightIndexed")
        reduceRightIndexedOrNull = interner.intern("reduceRightIndexedOrNull")
        reduceRightOrNull = interner.intern("reduceRightOrNull")
        reduceTo = interner.intern("reduceTo")
        remove = interner.intern("remove")
        removeAll = interner.intern("removeAll")
        requireNoNulls = interner.intern("requireNoNulls")
        retainAll = interner.intern("retainAll")
        reversed = interner.intern("reversed")
        runningFold = interner.intern("runningFold")
        runningFoldIndexed = interner.intern("runningFoldIndexed")
        runningReduce = interner.intern("runningReduce")
        runningReduceIndexed = interner.intern("runningReduceIndexed")
        scan = interner.intern("scan")
        scanIndexed = interner.intern("scanIndexed")
        scanReduce = interner.intern("scanReduce")
        shuffled = interner.intern("shuffled")
        single = interner.intern("single")
        singleOrNull = interner.intern("singleOrNull")
        slice = interner.intern("slice")
        sort = interner.intern("sort")
        sortBy = interner.intern("sortBy")
        sortByDescending = interner.intern("sortByDescending")
        sorted = interner.intern("sorted")
        sortedBy = interner.intern("sortedBy")
        sortedByDescending = interner.intern("sortedByDescending")
        sortedDescending = interner.intern("sortedDescending")
        sortedWith = interner.intern("sortedWith")
        step = interner.intern("step")
        subList = interner.intern("subList")
        subtract = interner.intern("subtract")
        sum = interner.intern("sum")
        sumBy = interner.intern("sumBy")
        sumByDouble = interner.intern("sumByDouble")
        sumOf = interner.intern("sumOf")
        take = interner.intern("take")
        toBooleanArray = interner.intern("toBooleanArray")
        toByteArray = interner.intern("toByteArray")
        toCharArray = interner.intern("toCharArray")
        toCollection = interner.intern("toCollection")
        toDoubleArray = interner.intern("toDoubleArray")
        toFloatArray = interner.intern("toFloatArray")
        toIntArray = interner.intern("toIntArray")
        toList = interner.intern("toList")
        toLongArray = interner.intern("toLongArray")
        toMutableList = interner.intern("toMutableList")
        toShortArray = interner.intern("toShortArray")
        toTypedArray = interner.intern("toTypedArray")
        toUByteArray = interner.intern("toUByteArray")
        toUIntArray = interner.intern("toUIntArray")
        toULongArray = interner.intern("toULongArray")
        toUShortArray = interner.intern("toUShortArray")
        trimMargin = interner.intern("trimMargin")
        typeOf = interner.intern("typeOf")
        union = interner.intern("union")
        unzip = interner.intern("unzip")
        windowed = interner.intern("windowed")
        withDefault = interner.intern("withDefault")
        withIndex = interner.intern("withIndex")
        zip = interner.intern("zip")
        zipWithNext = interner.intern("zipWithNext")
        pair = interner.intern("Pair")
        iterable = interner.intern("Iterable")
        comparator = interner.intern("Comparator")
        sequenceScope = interner.intern("SequenceScope")
        closedFloatingPointRange = interner.intern("ClosedFloatingPointRange")
        self.kotlin = kotlin
        sequences = interner.intern("sequences")
        initName = interner.intern("<init>")
        invoke = interner.intern("invoke")
        yield = interner.intern("yield")
        yieldAll = interner.intern("yieldAll")
        comparisons = interner.intern("comparisons")

        let kotlinRanges = interner.intern("ranges")
        let kotlinTime = interner.intern("time")
        let kotlinMath = interner.intern("math")
        kotlinCollectionsPackage = [kotlin, kotlinCollections]
        kotlinSequencesPackage = [kotlin, kotlinSequences]
        kotlinRangesPackage = [kotlin, kotlinRanges]
        kotlinTextPackage = [kotlin, kotlinText]
        kotlinTimePackage = [kotlin, kotlinTime]
        kotlinMathPackage = [kotlin, kotlinMath]
        kotlinArrayFQName = [kotlin, array]
        kotlinPairFQName = [kotlin, pair]
        kotlinComparatorFQName = [kotlin, comparator]
        kotlinIntArrayFQName = [kotlin, intArray]
        kotlinLongArrayFQName = [kotlin, longArray]
        kotlinShortArrayFQName = [kotlin, shortArray]
        kotlinByteArrayFQName = [kotlin, byteArray]
        kotlinUByteArrayFQName = [kotlin, ubyteArray]
        kotlinUShortArrayFQName = [kotlin, ushortArray]
        kotlinUIntArrayFQName = [kotlin, uintArray]
        kotlinULongArrayFQName = [kotlin, ulongArray]
        kotlinDoubleArrayFQName = [kotlin, doubleArray]
        kotlinFloatArrayFQName = [kotlin, floatArray]
        kotlinBooleanArrayFQName = [kotlin, booleanArray]
        kotlinCharArrayFQName = [kotlin, charArray]
        kotlinCollectionsMutableIterableFQName = [kotlin, kotlinCollections, interner.intern("MutableIterable")]
        kotlinCollectionsIndexedValueFQName = [kotlin, kotlinCollections, interner.intern("IndexedValue")]
        kotlinCollectionsIteratorFQName = [kotlin, kotlinCollections, interner.intern("Iterator")]
        kotlinCollectionsMutableIteratorFQName = [kotlin, kotlinCollections, interner.intern("MutableIterator")]
        kotlinCollectionsMapEntryFQName = [kotlin, kotlinCollections, map, interner.intern("Entry")]
        kotlinRangesCharRangeFQName = [kotlin, kotlinRanges, charRange]
        kotlinRangesClosedFloatingPointRangeFQName = [kotlin, kotlinRanges, closedFloatingPointRange]
        kotlinTimeInstantFQName = [kotlin, kotlinTime, interner.intern("Instant")]

        collectionMembers = Set(["size", "isEmpty", "contains", "containsAll", "first", "last", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast", "count", "iterator", "filter", "filterNotNull", "filterIsInstanceTo", "filterNotNullTo", "fold", "foldRight", "foldIndexed", "foldRightIndexed", "reduce", "reduceRight", "reduceRightIndexed", "reduceRightIndexedOrNull", "reduceRightOrNull", "reduceOrNull", "reduceIndexed", "reduceIndexedOrNull", "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "scanReduce", "sortedBy", "find", "zip", "unzip", "withIndex", "min", "maxOrNull", "minOrNull", "asSequence", "asIterable", "toList", "toCollection", "toTypedArray", "toCharArray", "toBooleanArray", "toShortArray", "toDoubleArray", "toFloatArray", "toIntArray", "toLongArray", "toByteArray", "toUByteArray", "toUShortArray", "toUIntArray", "toULongArray", "take", "drop", "reversed", "asReversed", "sorted", "shuffled", "distinct", "distinctBy", "flatten", "chunked", "windowed", "firstNotNullOf", "firstNotNullOfOrNull", "sortedDescending", "sortedByDescending", "sortedWith", "partition", "filterIsInstance", "firstOrNull", "lastOrNull", "singleOrNull", "joinToString", "elementAt", "single", "toMutableList", "sum", "average", "minusElement"].map { interner.intern($0) })
        listOnlyMembers = Set(["get", "subList", "slice", "getOrNull", "elementAtOrNull", "binarySearch", "binarySearchBy"].map { interner.intern($0) })
        collectionSpecificMembers = Set(["firstOrNull", "lastOrNull", "singleOrNull"].map { interner.intern($0) })
        mutableListOnlyMembers = Set(["sort", "sortBy", "sortByDescending"].map { interner.intern($0) })
        mutableCollectionMembers = Set(["add", "addAll", "remove", "removeAll", "retainAll", "clear"].map { interner.intern($0) })
        mapOnlyMembers = Set(["containsKey", "containsValue", "getValue", "getOrDefault", "plus"].map { interner.intern($0) })
        collectionReturningMembers = Set(["asSequence", "asIterable", "filterNotNull", "requireNoNulls", "filter", "filterIsInstanceTo", "reduceTo", "zip", "toList", "toTypedArray", "take", "drop", "reversed", "asReversed", "sorted", "distinct", "distinctBy", "flatten", "chunked", "windowed", "withIndex", "shuffled", "sortedDescending", "sortedByDescending", "sortedWith", "filterIsInstance", "toCollection", "subList", "slice", "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "scanReduce", "toMutableList", "minusElement"].map { interner.intern($0) })
        intReturningMembers = Set(["size", "indexOf", "lastIndexOf", "indexOfFirst", "indexOfLast", "count", "binarySearch", "binarySearchBy"].map { interner.intern($0) })
        boolReturningMembers = Set(["isEmpty", "contains", "containsAll", "containsKey", "containsValue", "add", "addAll", "remove", "removeAll", "retainAll"].map { interner.intern($0) })
        destinationCollectionReturningMembers = Set(["filterIsInstanceTo", "filterNotNullTo", "reduceTo", "toCollection"].map { interner.intern($0) })
        listPreservingMembers = Set(["sorted", "sortedDescending", "sortedWith", "shuffled", "reversed", "asReversed", "distinct", "distinctBy"].map { interner.intern($0) })
        boolOneParamMembers = Set(["filter", "count", "first", "last", "single", "find", "indexOfFirst", "indexOfLast", "partition"].map { interner.intern($0) })
        oneParamMembers = Set(["filter", "sortedBy", "count", "first", "last", "single", "find", "sortedByDescending", "partition", "sortBy", "sortByDescending", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull", "maxOf", "minOf"].map { interner.intern($0) })
        setReturningCollectionBinaryMembers = Set(["intersect", "union", "subtract"].map { interner.intern($0) })
        bundledRangeSourceMemberNames = Set(["contains", "isEmpty", "iterator", "toList", "forEach", "map", "mapIndexed", "mapNotNull", "filter", "filterIndexed", "filterNot", "take", "drop", "chunked", "windowed", "sorted", "average", "random", "randomOrNull", "step", "plus", "minus"].map { interner.intern($0) })
        rangeMigrationMemberNames = Set(["iterator", "step", "take", "drop", "chunked", "windowed"].map { interner.intern($0) })
        progressionFirstLastMemberNames = Set(["first", "firstOrNull", "last", "lastOrNull"].map { interner.intern($0) })
        instantValueSemanticsMemberNames = Set(["equals", "hashCode", "toString"].map { interner.intern($0) })
    }

    func builtinType(named name: InternedString, nullability: Nullability = .nonNull, types: TypeSystem) -> TypeID? {
        switch name {
        case byte:
            types.withNullability(nullability, for: types.byteType)
        case short:
            types.withNullability(nullability, for: types.shortType)
        case int:
            types.withNullability(nullability, for: types.intType)
        case long:
            types.withNullability(nullability, for: types.longType)
        case float:
            types.withNullability(nullability, for: types.floatType)
        case double:
            types.withNullability(nullability, for: types.doubleType)
        case boolean:
            types.withNullability(nullability, for: types.booleanType)
        case char:
            types.withNullability(nullability, for: types.charType)
        case string:
            types.withNullability(nullability, for: types.stringType)
        case uint:
            types.withNullability(nullability, for: types.uintType)
        case ulong:
            types.withNullability(nullability, for: types.ulongType)
        case ubyte:
            types.withNullability(nullability, for: types.ubyteType)
        case ushort:
            types.withNullability(nullability, for: types.ushortType)
        case any:
            types.withNullability(nullability, for: types.anyType)
        case unit:
            types.unitType
        case nothing:
            types.withNullability(nullability, for: types.nothingType)
        default:
            nil
        }
    }

    func symbolMatches(_ symbol: SemanticSymbol, fqName: [InternedString]) -> Bool {
        symbol.fqName == fqName
    }

    func isRegexSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == regex || symbolMatches(symbol, fqName: kotlinRegexFQName)
    }

    func isStringBuilderSymbol(_ symbol: SemanticSymbol) -> Bool {
        if symbolMatches(symbol, fqName: kotlinStringBuilderFQName) {
            return true
        }
        // Fall back to simple name match only for synthetic symbols (no FQN)
        return symbol.name == stringBuilder && symbol.fqName.isEmpty
    }

    /// True for runtime-backed atomic box classes whose constructors are
    /// factory functions (e.g. `kk_atomic_int_create`, `kk_atomic_int_array_create`)
    /// rather than `(this, value)` initializers. These classes must not allocate
    /// a generic `kk_object_new` instance before calling the constructor.
    ///
    /// Includes the source-backed `kotlin.concurrent` shells: claiming the
    /// synthetic class drops `.synthetic`, so constructor lowering has to
    /// recognize them by FQN rather than by the old special-call path.
    func isAtomicScalarFactorySymbol(_ symbol: SemanticSymbol) -> Bool {
        atomicScalarFactoryFQNames.contains(symbol.fqName)
    }

    func isSequenceSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == sequence || symbolMatches(symbol, fqName: kotlinSequenceFQName)
    }

    func isCoroutineHandleSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == job || symbol.name == deferred
            || symbolMatches(symbol, fqName: kotlinxCoroutinesJobFQName)
            || symbolMatches(symbol, fqName: kotlinxCoroutinesDeferredFQName)
    }

    func isChannelSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == channel || symbolMatches(symbol, fqName: kotlinxCoroutinesChannelFQName)
    }

    func isThrowableCatchAllSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == throwable || symbol.name == exception
    }

    func isCancellationExceptionSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == cancellationException
    }

    /// Short names of the built-in `kotlin.ranges` Range / Progression
    /// classes, unsigned variants included. For-loop lowering routes these
    /// classes through their bundled `iterator()` operators.
    func isRangeLikeClassName(_ name: InternedString) -> Bool {
        name == intRange || name == longRange || name == charRange
            || name == uintRange || name == ulongRange
            || name == intProgression || name == longProgression
            || name == charProgression || name == uintProgression
            || name == ulongProgression
    }

    /// The signed subset of `isRangeLikeClassName` (Int/Long/Char only).
    func isSignedRangeLikeClassName(_ name: InternedString) -> Bool {
        name == intRange || name == longRange || name == charRange
            || name == intProgression || name == longProgression
            || name == charProgression
    }

    /// True when `symbol` is a built-in `kotlin.ranges` Range / Progression
    /// class (unsigned variants included).
    func isRangeLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.fqName.starts(with: kotlinRangesPackageFQName)
            && (symbol.fqName.last.map { isRangeLikeClassName($0) } ?? false)
    }

    func isArrayLikeName(_ name: InternedString) -> Bool {
        name == array
            || name == intArray
            || name == longArray
            || name == shortArray
            || name == byteArray
            || name == ubyteArray
            || name == ushortArray
            || name == ulongArray
            || name == doubleArray
            || name == floatArray
            || name == booleanArray
            || name == charArray
            || name == uintArray
    }

    /// Returns true if the name is a primitive array constructor type name
    /// (e.g. Array, IntArray, LongArray, etc.).
    func isPrimitiveArrayConstructorTypeName(_ name: InternedString) -> Bool {
        name == array
            || name == intArray
            || name == longArray
            || name == shortArray
            || name == byteArray
            || name == ubyteArray
            || name == ushortArray
            || name == ulongArray
            || name == doubleArray
            || name == floatArray
            || name == booleanArray
            || name == charArray
            || name == uintArray
    }

    /// The set of stdlib collection factory function names used for marking
    /// collection literal expressions. Shared across call type-checking sites
    /// to avoid duplication.
    static let stdlibCollectionFactoryNames: Set<String> = [
        "listOf", "mutableListOf", "arrayListOf", "emptyList",
        "arrayOf", "emptyArray", "intArrayOf", "longArrayOf",
        "shortArrayOf", "byteArrayOf", "ubyteArrayOf", "ushortArrayOf", "uintArrayOf", "ulongArrayOf",
        "doubleArrayOf", "floatArrayOf", "booleanArrayOf", "charArrayOf",
        "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf", "emptyMap",
        "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf", "emptySet",
        "listOfNotNull",
        "sequenceOf", "generateSequence",
        "ArrayList",
        "HashMap", "LinkedHashMap",
        "HashSet", "LinkedHashSet",
    ]

    /// The subset of `stdlibCollectionFactoryNames` that produce `Array`/primitive-array
    /// literals rather than `List`/`Set`/`Map`/`Sequence` ones. Excluded from
    /// `markCollectionExpr` call sites: an `Array` receiver's runtime representation
    /// (RuntimeArrayBox) is not interchangeable with the List/Sequence-shaped box that
    /// collection member-call fallback resolution assumes, so flagging arrays as
    /// "collection expr" causes List/Sequence-only extension functions (e.g.
    /// `filterIsInstance`, `sortedBy`) to be resolved and lowered against the wrong
    /// runtime representation, corrupting memory or crashing.
    static let arrayFactoryFunctionNames: Set<String> = [
        "arrayOf", "emptyArray", "intArrayOf", "longArrayOf",
        "shortArrayOf", "byteArrayOf", "ubyteArrayOf", "ushortArrayOf", "uintArrayOf", "ulongArrayOf",
        "doubleArrayOf", "floatArrayOf", "booleanArrayOf", "charArrayOf",
    ]

    func isConcreteListLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == list || symbol.name == mutableList
            || symbolMatches(symbol, fqName: kotlinCollectionsArrayListFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsListFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableListFQName)
            // kotlin.enums.EnumEntries<T> is a read-only List<T> subtype (Kotlin
            // 1.9+ `EnumClass.entries`). Treat it exactly like List so the
            // collection member-call fallback (.size, .forEach, etc.) resolves.
            || symbolMatches(symbol, fqName: kotlinEnumsEnumEntriesFQName)
    }

    func isMapLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == map || symbol.name == mutableMap
            || symbolMatches(symbol, fqName: kotlinCollectionsMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashMapFQName)
            // KUU-556: LinkedHashMap is now a real HashMap subclass (its own
            // symbol), not a MutableMap typealias resolving straight through
            // to the mutableMap check above.
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashMapFQName)
    }

    func isMutableMapSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == mutableMap
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashMapFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashMapFQName)
    }

    func isMutableSetSymbol(_ symbol: SemanticSymbol) -> Bool {
        symbol.name == mutableSet || symbol.name == hashSet || symbol.name == linkedHashSet
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashSetFQName)
    }

    func isSetLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        if symbolMatches(symbol, fqName: kotlinCollectionsSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsHashSetFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsLinkedHashSetFQName)
        {
            return true
        }
        // Fall back to simple name match only for synthetic symbols (no FQN)
        return (symbol.name == set
            || symbol.name == mutableSet
            || symbol.name == hashSet
            || symbol.name == linkedHashSet)
            && symbol.fqName.isEmpty
    }

    func isCollectionLikeSymbol(_ symbol: SemanticSymbol) -> Bool {
        isConcreteListLikeSymbol(symbol)
            || symbol.name == collection
            || symbol.name == mutableCollection
            || isSetLikeSymbol(symbol)
            || symbolMatches(symbol, fqName: kotlinCollectionsCollectionFQName)
            || symbolMatches(symbol, fqName: kotlinCollectionsMutableCollectionFQName)
            || isMapLikeSymbol(symbol)
            || isSequenceSymbol(symbol)
    }

    func collectionKind(of symbol: SemanticSymbol) -> KnownCollectionKind? {
        if isMapLikeSymbol(symbol) {
            return .map
        }
        if isSetLikeSymbol(symbol) {
            return .set
        }
        if isArrayLikeName(symbol.name) {
            return .array
        }
        if isConcreteListLikeSymbol(symbol) {
            return .list
        }
        if symbol.name == collection || symbolMatches(symbol, fqName: kotlinCollectionsCollectionFQName) {
            return .collection
        }
        if isSequenceSymbol(symbol) {
            return .sequence
        }
        return nil
    }
}
