#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Test vocabulary for compiler/runtime boundaries. Keep ABI spelling here;
/// assertions inspect interned targets and the call's operands and effects.
enum KIRRuntimeFunction {
    case arrayNewChecked, arrayGet, arrayGetInbounds, arraySet
    case objectNew, objectTypeID, registerITableInterface, registerITableMethod, abortUnreachable
    case lateinitGetOrThrow, lateinitIsInitialized
    case functionInvoke(arity: Int), functionCreate(arity: Int), functionTagArity
    case functionSetDescription, functionCopyDescription, callableName, tagKFunction, tagKProperty
    case kClassCreate, kClassOf, kClassFindAssociatedObject, kClassMetadata, kClassCast, kClassSafeCast
    case observableCreate, opIs
    case rangeFirst, rangeLast, floatingRangeEndpoint
    case doubleRangeStart, doubleRangeEndInclusive, floatRangeStart, floatRangeEndInclusive
    case unboxInt, unboxDouble, unboxFloat
    case intToByte, intToShort, intToUByte, intToUShort, intToChar
    case regexCreateWithOption, regexCreateWithOptions
    case mapGet, mapIsEmpty, mapKeys
    case printRaw

    func name(in interner: StringInterner) -> InternedString {
        let linkName: String
        switch self {
        case .arrayNewChecked: linkName = "kk_array_new_checked"
        case .arrayGet: linkName = "kk_array_get"
        case .arrayGetInbounds: linkName = "kk_array_get_inbounds"
        case .arraySet: linkName = "kk_array_set"
        case .objectNew: linkName = "kk_object_new"
        case .objectTypeID: linkName = "kk_object_type_id"
        case .registerITableInterface: linkName = "kk_object_register_itable_iface"
        case .registerITableMethod: linkName = "kk_object_register_itable_method"
        case .abortUnreachable: linkName = "kk_abort_unreachable"
        case .lateinitGetOrThrow: linkName = "kk_lateinit_get_or_throw"
        case .lateinitIsInitialized: linkName = "kk_lateinit_is_initialized"
        case let .functionInvoke(arity): linkName = arity == 1 ? "kk_function_invoke" : "kk_function_invoke_\(arity)"
        case let .functionCreate(arity): linkName = "kk_function_create_\(arity)"
        case .functionTagArity: linkName = "kk_function_value_tag_arity"
        case .functionSetDescription: linkName = "__kk_function_set_description"
        case .functionCopyDescription: linkName = "__kk_function_copy_description"
        case .callableName: linkName = "__kk_kcallable_get_name"
        case .tagKFunction: linkName = "kk_callable_ref_tag_kfunction"
        case .tagKProperty: linkName = "kk_callable_ref_tag_kproperty"
        case .kClassCreate: linkName = "__kk_kclass_create"
        case .kClassOf: linkName = "__kk_kclass_of"
        case .kClassFindAssociatedObject: linkName = "__kk_kclass_find_associated_object"
        case .kClassMetadata: linkName = "__kk_kclass_register_metadata"
        case .kClassCast: linkName = "__kk_kclass_cast"
        case .kClassSafeCast: linkName = "__kk_kclass_safeCast"
        case .observableCreate: linkName = "kk_observable_create"
        case .opIs: linkName = "kk_op_is"
        case .rangeFirst: linkName = "__kk_range_first"
        case .rangeLast: linkName = "__kk_range_last"
        case .floatingRangeEndpoint: linkName = "__kk_floating_range_endpoint_or_null"
        case .doubleRangeStart: linkName = "__kk_double_range_start"
        case .doubleRangeEndInclusive: linkName = "__kk_double_range_endInclusive"
        case .floatRangeStart: linkName = "__kk_float_range_start"
        case .floatRangeEndInclusive: linkName = "__kk_float_range_endInclusive"
        case .unboxInt: linkName = "kk_unbox_int"
        case .unboxDouble: linkName = "kk_unbox_double"
        case .unboxFloat: linkName = "kk_unbox_float"
        case .intToByte: linkName = "kk_int_to_byte"
        case .intToShort: linkName = "kk_int_to_short"
        case .intToUByte: linkName = "kk_int_to_ubyte"
        case .intToUShort: linkName = "kk_int_to_ushort"
        case .intToChar: linkName = "kk_int_to_char"
        case .regexCreateWithOption: linkName = "__kk_regex_create_with_option_flat"
        case .regexCreateWithOptions: linkName = "__kk_regex_create_with_options_flat"
        case .mapGet: linkName = "__kk_map_get"
        case .mapIsEmpty: linkName = "__kk_map_is_empty"
        case .mapKeys: linkName = "__kk_map_keys"
        case .printRaw: linkName = "__kk_print_raw"
        }
        return interner.intern(linkName)
    }
}

struct KIRCallSite {
    let index: Int
    let symbol: SymbolID?
    let callee: InternedString
    let arguments: [KIRExprID]
    let result: KIRExprID?
    let canThrow: Bool
    let thrownResult: KIRExprID?
    let isSuperCall: Bool
    let qualifiedSuperType: SymbolID?
}

/// Preserve instruction indices so ordering checks share the same call view
/// as argument, result, and exception-routing checks.
func kirCalls(in body: [KIRInstruction]) -> [KIRCallSite] {
    body.enumerated().compactMap { index, instruction in
        guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType) = instruction
        else { return nil }
        return KIRCallSite(
            index: index, symbol: symbol, callee: callee, arguments: arguments,
            result: result, canThrow: canThrow, thrownResult: thrownResult,
            isSuperCall: isSuperCall, qualifiedSuperType: qualifiedSuperType
        )
    }
}

func kirCalls(
    to runtime: KIRRuntimeFunction,
    in body: [KIRInstruction],
    interner: StringInterner
) -> [KIRCallSite] {
    let callee = runtime.name(in: interner)
    return kirCalls(in: body).filter { $0.callee == callee }
}

func kirCalls(to symbol: SymbolID, in body: [KIRInstruction]) -> [KIRCallSite] {
    kirCalls(in: body).filter { $0.symbol == symbol }
}

func kirFunctionCreationCalls(in body: [KIRInstruction], interner: StringInterner) -> [KIRCallSite] {
    // Include unsupported arities so negative assertions catch an accidental
    // object-creation call even when its runtime export does not exist.
    kirCalls(in: body).filter { interner.resolve($0.callee).hasPrefix("kk_function_create_") }
}

func kClassExtensionGetter(named name: String, in context: CompilationContext) throws -> SymbolID {
    let sema = try #require(context.sema)
    let property = try #require(sema.symbols.lookup(
        fqName: ["kotlin", "reflect", name].map(context.interner.intern)
    ))
    return try #require(sema.symbols.extensionPropertyGetterAccessor(for: property))
}

func isKIRPrintCallee(
    _ callee: InternedString, interner: StringInterner, includeRawPrint: Bool = true
) -> Bool {
    callee == interner.intern("println")
        || (includeRawPrint && callee == KIRRuntimeFunction.printRaw.name(in: interner))
        || interner.resolve(callee).hasPrefix("kk_println")
}
#endif
