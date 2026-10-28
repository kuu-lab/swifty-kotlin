
struct CommonLookupNames {
    let sumName: InternedString
    let sizeName: InternedString
    let getName: InternedString
    let containsName: InternedString
    let isEmptyName: InternedString
    let countName: InternedString
    let addName: InternedString
    let removeName: InternedString
    let firstName: InternedString
    let lastName: InternedString
    let startName: InternedString
    let endInclusiveName: InternedString
    let endExclusiveName: InternedString
    let stepName: InternedString
    let iteratorName: InternedString
    let mapName: InternedString
    let filterName: InternedString
    let filterNotName: InternedString
    let mapNotNullName: InternedString
    let requireNoNullsName: InternedString
    let mapToName: InternedString
    let flatMapToName: InternedString
    let mapNotNullToName: InternedString
    let mapIndexedToName: InternedString
    let mapIndexedNotNullToName: InternedString
    let flatMapIndexedToName: InternedString
    let forEachName: InternedString
    let flatMapName: InternedString
    let flatMapIndexedName: InternedString
    let anyName: InternedString
    let noneName: InternedString
    let allName: InternedString
    let foldName: InternedString
    let reduceName: InternedString
    let scanName: InternedString
    let runningFoldName: InternedString
    let runningReduceName: InternedString
    let groupByName: InternedString
    let findName: InternedString
    let findLastName: InternedString
    let associateByName: InternedString
    let associateWithName: InternedString
    let associateName: InternedString
    let associateToName: InternedString
    let associateByToName: InternedString
    let associateWithToName: InternedString
    let groupByToName: InternedString
    let mapValuesName: InternedString
    let mapKeysName: InternedString
    let filterKeysName: InternedString
    let filterValuesName: InternedString
    let zipName: InternedString
    let zipWithNextName: InternedString
    let unzipName: InternedString
    let onEachName: InternedString
    let onEachIndexedName: InternedString
    let mapIndexedName: InternedString
    let mapIndexedNotNullName: InternedString
    let foldIndexedName: InternedString
    let reduceIndexedName: InternedString
    let filterIndexedName: InternedString
    let runningFoldIndexedName: InternedString
    let runningReduceIndexedName: InternedString
    let scanIndexedName: InternedString
    let maxName: InternedString
    let maxOrNullName: InternedString
    let minOrNullName: InternedString
    let dropName: InternedString
    let reversedName: InternedString
    let asReversedName: InternedString
    let sortedName: InternedString
    let averageName: InternedString
    let distinctName: InternedString
    let shuffledName: InternedString
    let flattenName: InternedString
    let chunkedName: InternedString
    let windowedName: InternedString
    let partitionName: InternedString
    let takeWhileName: InternedString
    let dropWhileName: InternedString
    let takeLastWhileName: InternedString
    let dropLastWhileName: InternedString
    let firstOrNullName: InternedString
    let lastOrNullName: InternedString
    let emptyListFQName: [InternedString]
    let emptyArrayFQName: [InternedString]
    let emptySetFQName: [InternedString]
    let emptyMapFQName: [InternedString]
    let listOfFQName: [InternedString]
    let setOfFQName: [InternedString]
    let setOfNotNullFQName: [InternedString]
    let mapOfFQName: [InternedString]
    let mutableListOfFQName: [InternedString]
    let arrayListOfFQName: [InternedString]
    let mutableSetOfFQName: [InternedString]
    let linkedSetOfFQName: [InternedString]
    let hashSetOfFQName: [InternedString]
    let mutableMapOfFQName: [InternedString]
    let hashMapOfFQName: [InternedString]
    let linkedMapOfFQName: [InternedString]
    let listOfNotNullFQName: [InternedString]
    let kotlinName: InternedString
    let initName: InternedString
    let kkPairFirstName: InternedString
    let kkPairSecondName: InternedString

    init(interner: StringInterner) {
        sumName = interner.intern("sum")
        sizeName = interner.intern("size")
        getName = interner.intern("get")
        containsName = interner.intern("contains")
        isEmptyName = interner.intern("isEmpty")
        countName = interner.intern("count")
        addName = interner.intern("add")
        removeName = interner.intern("remove")
        firstName = interner.intern("first")
        lastName = interner.intern("last")
        startName = interner.intern("start")
        endInclusiveName = interner.intern("endInclusive")
        endExclusiveName = interner.intern("endExclusive")
        stepName = interner.intern("step")
        iteratorName = interner.intern("iterator")
        mapName = interner.intern("map")
        filterName = interner.intern("filter")
        filterNotName = interner.intern("filterNot")
        mapNotNullName = interner.intern("mapNotNull")
        requireNoNullsName = interner.intern("requireNoNulls")
        mapToName = interner.intern("mapTo")
        flatMapToName = interner.intern("flatMapTo")
        mapNotNullToName = interner.intern("mapNotNullTo")
        mapIndexedToName = interner.intern("mapIndexedTo")
        mapIndexedNotNullToName = interner.intern("mapIndexedNotNullTo")
        flatMapIndexedToName = interner.intern("flatMapIndexedTo")
        forEachName = interner.intern("forEach")
        flatMapName = interner.intern("flatMap")
        flatMapIndexedName = interner.intern("flatMapIndexed")
        anyName = interner.intern("any")
        noneName = interner.intern("none")
        allName = interner.intern("all")
        foldName = interner.intern("fold")
        reduceName = interner.intern("reduce")
        scanName = interner.intern("scan")
        runningFoldName = interner.intern("runningFold")
        runningReduceName = interner.intern("runningReduce")
        groupByName = interner.intern("groupBy")
        findName = interner.intern("find")
        findLastName = interner.intern("findLast")
        associateByName = interner.intern("associateBy")
        associateWithName = interner.intern("associateWith")
        associateName = interner.intern("associate")
        associateToName = interner.intern("associateTo")
        associateByToName = interner.intern("associateByTo")
        associateWithToName = interner.intern("associateWithTo")
        groupByToName = interner.intern("groupByTo")
        mapValuesName = interner.intern("mapValues")
        mapKeysName = interner.intern("mapKeys")
        filterKeysName = interner.intern("filterKeys")
        filterValuesName = interner.intern("filterValues")
        zipName = interner.intern("zip")
        zipWithNextName = interner.intern("zipWithNext")
        unzipName = interner.intern("unzip")
        onEachName = interner.intern("onEach")
        onEachIndexedName = interner.intern("onEachIndexed")
        mapIndexedName = interner.intern("mapIndexed")
        mapIndexedNotNullName = interner.intern("mapIndexedNotNull")
        foldIndexedName = interner.intern("foldIndexed")
        reduceIndexedName = interner.intern("reduceIndexed")
        filterIndexedName = interner.intern("filterIndexed")
        runningFoldIndexedName = interner.intern("runningFoldIndexed")
        runningReduceIndexedName = interner.intern("runningReduceIndexed")
        scanIndexedName = interner.intern("scanIndexed")
        maxName = interner.intern("max")
        maxOrNullName = interner.intern("maxOrNull")
        minOrNullName = interner.intern("minOrNull")
        dropName = interner.intern("drop")
        reversedName = interner.intern("reversed")
        asReversedName = interner.intern("asReversed")
        sortedName = interner.intern("sorted")
        averageName = interner.intern("average")
        distinctName = interner.intern("distinct")
        shuffledName = interner.intern("shuffled")
        flattenName = interner.intern("flatten")
        chunkedName = interner.intern("chunked")
        windowedName = interner.intern("windowed")
        partitionName = interner.intern("partition")
        takeWhileName = interner.intern("takeWhile")
        dropWhileName = interner.intern("dropWhile")
        takeLastWhileName = interner.intern("takeLastWhile")
        dropLastWhileName = interner.intern("dropLastWhile")
        firstOrNullName = interner.intern("firstOrNull")
        lastOrNullName = interner.intern("lastOrNull")
        let kotlinCollectionsPkg = [interner.intern("kotlin"), interner.intern("collections")]
        emptyListFQName = kotlinCollectionsPkg + [interner.intern("emptyList")]
        emptyArrayFQName = [interner.intern("kotlin")] + [interner.intern("emptyArray")]
        emptySetFQName = kotlinCollectionsPkg + [interner.intern("emptySet")]
        emptyMapFQName = kotlinCollectionsPkg + [interner.intern("emptyMap")]
        listOfFQName = kotlinCollectionsPkg + [interner.intern("listOf")]
        setOfFQName = kotlinCollectionsPkg + [interner.intern("setOf")]
        setOfNotNullFQName = kotlinCollectionsPkg + [interner.intern("setOfNotNull")]
        mapOfFQName = kotlinCollectionsPkg + [interner.intern("mapOf")]
        mutableListOfFQName = kotlinCollectionsPkg + [interner.intern("mutableListOf")]
        arrayListOfFQName = kotlinCollectionsPkg + [interner.intern("arrayListOf")]
        mutableSetOfFQName = kotlinCollectionsPkg + [interner.intern("mutableSetOf")]
        linkedSetOfFQName = kotlinCollectionsPkg + [interner.intern("linkedSetOf")]
        hashSetOfFQName = kotlinCollectionsPkg + [interner.intern("hashSetOf")]
        mutableMapOfFQName = kotlinCollectionsPkg + [interner.intern("mutableMapOf")]
        hashMapOfFQName = kotlinCollectionsPkg + [interner.intern("hashMapOf")]
        linkedMapOfFQName = kotlinCollectionsPkg + [interner.intern("linkedMapOf")]
        listOfNotNullFQName = kotlinCollectionsPkg + [interner.intern("listOfNotNull")]
        kotlinName = interner.intern("kotlin")
        initName = interner.intern("<init>")
        kkPairFirstName = interner.intern("__kk_pair_first")
        kkPairSecondName = interner.intern("__kk_pair_second")
    }
}
