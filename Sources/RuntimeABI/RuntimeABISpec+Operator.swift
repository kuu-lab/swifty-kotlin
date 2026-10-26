private let abi = RuntimeABISectionBuilder("TypeCheck")
private let abiReflection = RuntimeABISectionBuilder("Reflection")

public extension RuntimeABISpec {
    static let opIsSpec: RuntimeABIFunctionSpec = abi.nt("kk_op_is", "value typeToken")

    static let operatorFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("kk_type_register_super", "childTypeId superTypeId"),
        abi.nt("kk_type_register_iface", "childTypeId ifaceTypeId"),
        abi.nt("kk_object_register_itable_iface", "objectRaw ifaceTypeId ifaceSlot"),
        abi.nt("kk_object_register_itable_method", "objectRaw ifaceSlot methodSlot functionRaw"),
        abi.nt("kk_object_register_vtable_method", "objectRaw methodSlot functionRaw"),
        abi.nt("kk_object_register_equals_override", "objectRaw functionRaw"),
        abi.nt("kk_object_register_hashcode_override", "objectRaw functionRaw"),
        abi.nt("kk_object_register_any_to_string", "objectRaw functionRaw"),
        abi.nt("kk_value_class_register_any_to_string", "classID functionRaw"),
        abi.th("__kk_type_token_simple_name", "typeToken nameHint"),
        abi.th("__kk_type_token_qualified_name", "typeToken nameHint"),
        abi.nt("__kk_kclass_create", "typeToken nameHint"),
        abi.nt("__kk_kclass_of", "value fallbackToken nameHint"),
        abi.th("__kk_kclass_simple_name", "kclassRaw"),
        abi.th("__kk_kclass_qualified_name", "kclassRaw"),
        abi.th("__kk_kclass_register_display_name", "typeToken displayNameRaw"),
        abi.th("__kk_kclass_register_cast_name", "typeToken castNameRaw"),
        abi.nt("__kk_kclass_register_object", "typeToken objectRaw initializerRaw"),
        abi.th("__kk_kclass_object_instance", "kclassRaw outThrown"),
        abi.nt("__kk_kclass_register_sealed_subclass", "typeToken subclassToken nameHint"),
        abi.nt("__kk_kclass_sealed_subclasses", "kclassRaw"),
        abi.th("__kk_kclass_register_metadata", "typeToken qualifiedNameRaw simpleNameRaw supertypeNameRaw flags fieldCount memberCount constructorCount"),
        abi.nt("__kk_kclass_register_type_parameter", "typeToken index identity nameRaw varianceOrdinal isReified upperBoundsRaw"),
        abi.nt("__kk_kclass_register_enclosing_metadata", "typeToken enclosingClassNameRaw declaringClassNameRaw memberKind memberNameRaw memberSignatureRaw"),
        abi.nt("__kk_kclass_is_data", "kclassRaw"),
        abi.nt("__kk_kclass_is_sealed", "kclassRaw"),
        abi.nt("__kk_kclass_is_value", "kclassRaw"),
        abi.nt("__kk_kclass_is_interface", "kclassRaw"),
        abi.nt("__kk_kclass_is_object", "kclassRaw"),
        abi.nt("__kk_kclass_is_enum", "kclassRaw"),
        abi.nt("__kk_kclass_is_abstract", "kclassRaw"),
        abi.nt("__kk_kclass_is_inner", "kclassRaw"),
        abi.nt("__kk_kclass_is_companion", "kclassRaw"),
        abi.nt("__kk_kclass_is_fun", "kclassRaw"),
        abiReflection.th("__kk_kclass_get_annotations_typed", "kclassRaw outThrown"),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_find_annotation_typed",
            parameters: ["kclassRaw", "typeToken"].map { RuntimeABIParameter(name: $0, type: .intptr) }
                + [RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)],
            returnType: .intptr, section: "Reflection", isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_annotation_factory",
            parameters: ["typeToken", "fqNameRaw", "argsEncodedRaw", "argCount", "factory"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            }, returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        abiReflection.nt("__kk_kclass_is_runtime", "raw"),
        abiReflection.nt("__kk_kclass_get_annotations", "kclassRaw"),
        abiReflection.nt("__kk_kclass_find_associated_object", "kclassRaw keyNameRaw"),
        abiReflection.nt("__kk_kclass_register_single_annotation", "typeToken fqNameRaw argsEncodedRaw argCount"),
        abi.th("__kk_kclass_isInstance", "kclassRaw valueRaw"),
        abi.nt("__kk_java_class_isInstance", "classRaw valueRaw"),
        abi.nt("__kk_java_class_is_assignable_from", "classRaw otherClassRaw"),
        abi.th("__kk_kclass_cast", "kclassRaw valueRaw outThrown"),
        abi.nt("__kk_kclass_safeCast", "kclassRaw valueRaw"),
        abi.nt("__kk_java_class_get_declared_methods", "classRaw"),
        abi.nt("__kk_java_class_get_methods", "classRaw"),
        abi.nt("__kk_java_class_get_declared_method", "classRaw nameRaw parameterTypesRaw"),
        abi.nt("__kk_java_class_get_declared_field", "classRaw nameRaw"),
        abiReflection.th("__kk_java_class_get_annotations_typed", "classRaw outThrown"),
        abiReflection.nt("__kk_java_class_register_inherited_annotation", "annotationNameRaw"),
        abi.nt("__kk_java_class_get_name", "classRaw"),
        abi.nt("__kk_class_simple_name", "classRaw"),
        abi.nt("__kk_java_class_register_declared_method", "typeToken methodNameRaw signatureRaw flags"),
        abi.nt("__kk_java_class_register_declared_field", "typeToken fieldNameRaw"),
        RuntimeABIFunctionSpec(
            name: "__kk_java_field_register_single_annotation",
            parameters: ["typeToken", "fieldNameRaw", "fqNameRaw", "argsEncodedRaw", "argCount"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            },
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_field_register_annotation_factory",
            parameters: ["typeToken", "fieldNameRaw", "fqNameRaw", "argsEncodedRaw", "argCount", "factory"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            },
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        abiReflection.th("__kk_java_field_get_annotations_typed", "fieldRaw outThrown"),
        abi.nt("__kk_java_method_get_name", "methodRaw"),
        abi.nt("__kk_java_method_get_return_type", "methodRaw"),
        abi.nt("__kk_java_method_is_synthetic", "methodRaw"),
        abi.th("__kk_kclass_members", "kclassRaw"),
        abi.th("__kk_kclass_constructors", "kclassRaw"),
        // MIGRATION-REFLECT-002: KClass.nestedClasses
        abi.th("__kk_kclass_nested_classes", "kclassRaw"),
        abi.nt("__kk_kclass_companion_object", "kclassRaw"),
        abi.nt("__kk_kclass_register_companion", "typeToken companionToken companionNameRaw"),
        abi.nt("__kk_kclass_register_nested_class", "typeToken nestedToken nestedNameRaw"),
        abi.th("__kk_kclass_primary_constructor", "kclassRaw"),

        abi.th("__kk_kclass_properties", "kclassRaw"),
        abi.th("__kk_kclass_member_properties", "kclassRaw"),
        abi.th("__kk_kclass_declared_member_properties", "kclassRaw"),
        abi.th("__kk_kclass_functions", "kclassRaw"),
        abi.th("__kk_kclass_member_functions", "kclassRaw"),
        abi.th("__kk_kclass_declared_member_functions", "kclassRaw"),
        abi.nt("__kk_ktype_classifier", "ktypeRaw"),
        abi.nt("__kk_ktype_arguments", "ktypeRaw"),
        abi.nt("__kk_ktype_isMarkedNullable", "ktypeRaw"),
        abi.nt("__kk_ktype_create", "classifierRaw argsRaw isNullable"),
        abi.nt("__kk_ktypeparameter_create", "identity nameRaw varianceOrdinal isReified"),
        abi.nt("__kk_ktypeparameter_set_upper_bounds", "parameterRaw boundsRaw"),
        abi.nt("__kk_ktypeparameter_is_runtime", "parameterRaw"),
        abi.nt("__kk_ktypeparameter_get_name", "parameterRaw"),
        abi.nt("__kk_ktypeprojection_create", "typeRaw varianceOrdinal"),
        abi.th("__kk_ktypeprojection_create_checked", "varianceOrdinal typeRaw outThrown"),
        abi.nt("__kk_ktypeprojection_star"),
        abi.nt("__kk_ktypeprojection_get_variance", "projectionRaw"),
        abi.nt("__kk_ktypeprojection_get_type", "projectionRaw"),
        abi.nt("kk_typeof", "typeToken nameHint argsRaw isNullable"),
        opIsSpec,
        abi.th("kk_op_cast", "value typeToken outThrown"),
        abi.th("kk_op_cast_erased_return", "value typeToken outThrown"),
        abi.nt("kk_op_safe_cast", "value typeToken"),
        abi.th("kk_array_op_cast", "value typeToken componentType outThrown"),
        abi.nt("kk_array_op_safe_cast", "value typeToken componentType"),
        abi.nt("kk_op_contains", "container element"),
    ]
}
