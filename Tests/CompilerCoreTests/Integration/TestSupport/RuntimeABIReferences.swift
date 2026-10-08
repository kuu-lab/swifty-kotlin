import RuntimeABI
import Testing

/// Logical runtime operations used by Sema tests. The C link name (including
/// bridge visibility) comes from the ABI catalog, never from the test case.
enum SemaRuntimeFunction: String {
    case accessDeniedExceptionNewFile = "access_denied_exception_new_file"
    case accessDeniedExceptionNewFileOther = "access_denied_exception_new_file_other"
    case accessDeniedExceptionNewFileOtherReason = "access_denied_exception_new_file_other_reason"
    case arrayDequeNew = "arraydeque_new"
    case arrayDequeNewFromCollection = "arraydeque_new_from_collection"
    case arrayDequeNewWithCapacity = "arraydeque_new_with_capacity"
    case arraySet = "array_set"
    case atomicIntArrayCreate = "atomic_int_array_create"
    case atomicIntCreate = "atomic_int_create"
    case atomicLongArrayCreate = "atomic_long_array_create"
    case atomicLongCreate = "atomic_long_create"
    case atomicRefCreate = "atomic_ref_create"
    case charRangeStep = "char_range_step"
    case charRangeToList = "char_range_toList"
    case collectionSize = "collection_size"
    case comparableCompareTo = "comparable_compareTo"
    case contextGetDispatch = "context_get_dispatch"
    case contextMinusKeyDispatch = "context_minusKey_dispatch"
    case contextPlusDispatch = "context_plus_dispatch"
    case coroutineNameGet = "coroutine_name_get"
    case coroutineNameKey = "coroutine_name_key"
    case coroutineNameKeyGet = "coroutine_name_key_get"
    case fileAlreadyExistsExceptionNewFile = "file_already_exists_exception_new_file"
    case fileAlreadyExistsExceptionNewFileOther = "file_already_exists_exception_new_file_other"
    case fileAlreadyExistsExceptionNewFileOtherReason = "file_already_exists_exception_new_file_other_reason"
    case fileSystemExceptionNewFile = "file_system_exception_new_file"
    case fileSystemExceptionNewFileOther = "file_system_exception_new_file_other"
    case fileSystemExceptionNewFileOtherReason = "file_system_exception_new_file_other_reason"
    case functionCreate2 = "function_create_2"
    case functionInvoke = "function_invoke"
    case iterableAll = "iterable_all"
    case iterableAny = "iterable_any"
    case iterableFirstNotNullOf = "iterable_firstNotNullOf"
    case iterableIterator = "iterable_iterator"
    case jobIsActive = "job_is_active"
    case jobStart = "job_start"
    case kclassFindAssociatedObject = "kclass_find_associated_object"
    case listForEach = "list_forEach"
    case listIterator = "list_iterator"
    case listSubList = "list_subList"
    case longRangeFirstOrNull = "long_range_firstOrNull"
    case longRangeLastOrNull = "long_range_lastOrNull"
    case longRangeStep = "long_range_step"
    case mapEntries = "map_entries"
    case mapKeys = "map_keys"
    case mapValues = "map_values"
    case mutableCollectionAddAllThrowing = "mutable_collection_addAll_throwing"
    case mutableCollectionAddThrowing = "mutable_collection_add_throwing"
    case mutableCollectionClearThrowing = "mutable_collection_clear_throwing"
    case mutableCollectionRemoveAllThrowing = "mutable_collection_removeAll_throwing"
    case mutableCollectionRemoveThrowing = "mutable_collection_remove_throwing"
    case mutableCollectionRetainAllThrowing = "mutable_collection_retainAll_throwing"
    case mutableMapClear = "mutable_map_clear"
    case mutableMapPut = "mutable_map_put"
    case mutableMapPutAll = "mutable_map_putAll"
    case mutableMapRemove = "mutable_map_remove"
    case noSuchFileExceptionNewFile = "no_such_file_exception_new_file"
    case noSuchFileExceptionNewFileOther = "no_such_file_exception_new_file_other"
    case noSuchFileExceptionNewFileOtherReason = "no_such_file_exception_new_file_other_reason"
    case objectNew = "object_new"
    case objectRegisterVtableMethod = "object_register_vtable_method"
    case opStep = "op_step"
    case pairFirst = "pair_first"
    case rangeContains = "range_contains"
    case rangeFirstOrNullPredicate = "range_firstOrNull_predicate"
    case rangeLastOrNullPredicate = "range_lastOrNull_predicate"
    case regexCreateFlat = "regex_create_flat"
    case regexCreateWithOptionFlat = "regex_create_with_option_flat"
    case regexCreateWithOptionsFlat = "regex_create_with_options_flat"
    case regexFromLiteralFlat = "regex_from_literal_flat"
    case sequenceFirstOrNull = "sequence_firstOrNull"
    case sequenceToHashSet = "sequence_toHashSet"
    case stringContainsRegexFlat = "string_contains_regex_flat"
    case stringLowercaseFlat = "string_lowercase_flat"
    case stringSplitRegexFlat = "string_split_regex_flat"
    case stringToRegexFlat = "string_toRegex_flat"
    case stringToRegexWithOptionFlat = "string_toRegex_with_option_flat"
    case stringToRegexWithOptionsFlat = "string_toRegex_with_options_flat"
    case typeOf = "typeof"
    case uintRangeReduce = "uint_range_reduce"
    case uintRangeStep = "uint_range_step"
    case ulongRangeStep = "ulong_range_step"
    case withTimeout = "with_timeout"
    case withTimeoutOrNull = "with_timeout_or_null"
    case withTimeoutOrNullThrowing = "with_timeout_or_null_throwing"
}

private let semaRuntimeFunctionsByOperation = Dictionary(
    grouping: RuntimeABISpec.allFunctions,
    by: { runtimeABIOperation(of: $0.name) ?? $0.name }
)

/// Missing or ambiguous ABI entries fail even when a caller asserts absence.
/// Never invent a fallback link name for an operation absent from the catalog.
func runtimeABIName(
    _ function: SemaRuntimeFunction,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) -> String {
    let specs = semaRuntimeFunctionsByOperation[function.rawValue] ?? []
    guard specs.count == 1, let spec = specs.first,
          let declaration = RuntimeABIExterns.externDecl(named: spec.name)
    else {
        Issue.record("Expected one runtime ABI entry for \(function.rawValue), found \(specs.count)",
                     sourceLocation: sourceLocation)
        return "<missing ABI: \(function.rawValue)>"
    }
    return declaration.name
}

private func runtimeABIOperation(of linkName: String) -> String? {
    if linkName.hasPrefix("__kk_") { return String(linkName.dropFirst(5)) }
    if linkName.hasPrefix("kk_") { return String(linkName.dropFirst(3)) }
    return nil
}

enum SemaRuntimeFamily: String {
    case uintRange = "uint_range"
    case ulongRange = "ulong_range"
}

func hasRuntimeABIFamily(_ linkName: String?, _ family: SemaRuntimeFamily) -> Bool {
    guard let linkName, let operation = runtimeABIOperation(of: linkName) else { return false }
    return operation.hasPrefix(family.rawValue + "_")
}

/// These migrations deleted their runtime entries. Guard both public and
/// internal spellings without requiring a nonexistent canonical ABI entry.
enum RemovedSemaRuntimeOperation: String {
    case iterableCount = "iterable_count"
    case listCount = "list_count"
    case matchGroupCollectionGet = "match_group_collection_get"
    case matchGroupCollectionGetAt = "match_group_collection_get_at"
    case matchResultComponent1 = "match_result_component1"
}

func hasRemovedRuntimeOperation(_ linkName: String, _ operation: RemovedSemaRuntimeOperation) -> Bool {
    runtimeABIOperation(of: linkName) == operation.rawValue
}

/// Reject direct calls to either visibility of a source-backed wrapper's bridge.
func hasRuntimeABIOperation(_ linkName: String, _ function: SemaRuntimeFunction) -> Bool {
    runtimeABIOperation(of: linkName) == runtimeABIOperation(of: runtimeABIName(function))
}

/// Legacy dispatch can produce this internal marker, although bundled range
/// HOF source takes precedence and no runtime ABI entry exists for it.
enum SemaCompilerDispatchOperation: String {
    case ulongRangeReduce = "ulong_range_reduce"
}

func isInternalCompilerDispatch(
    _ linkName: String?,
    _ operation: SemaCompilerDispatchOperation
) -> Bool {
    guard let linkName else { return false }
    return linkName.hasPrefix("__kk_") && runtimeABIOperation(of: linkName) == operation.rawValue
}
