import Foundation

private let runtimeJavaKnownKotlinNominalNames = [
    "kotlin.collections.List",
    "kotlin.collections.MutableList",
    "kotlin.collections.Set",
    "kotlin.collections.MutableSet",
    "kotlin.collections.Map",
    "kotlin.collections.MutableMap",
    "kotlin.collections.Map.Entry",
    "kotlin.collections.MutableMap.MutableEntry",
    "kotlin.collections.ArrayList",
    "kotlin.collections.HashSet",
    "kotlin.collections.LinkedHashSet",
    "kotlin.collections.HashMap",
    "kotlin.collections.LinkedHashMap",
    "kotlin.collections.EmptyList",
    "kotlin.collections.EmptySet",
    "kotlin.collections.EmptyMap",
    "kotlin.Exception",
    "kotlin.RuntimeException",
    "kotlin.IllegalArgumentException",
    "kotlin.IllegalStateException",
    "kotlin.ArithmeticException",
    "kotlin.AssertionError",
    "kotlin.ClassCastException",
    "kotlin.IndexOutOfBoundsException",
    "kotlin.ArrayIndexOutOfBoundsException",
    "kotlin.StringIndexOutOfBoundsException",
    "kotlin.NegativeArraySizeException",
    "kotlin.NullPointerException",
    "kotlin.NumberFormatException",
    "kotlin.UnsupportedOperationException",
    "kotlin.Error",
    "kotlin.OutOfMemoryError",
    "kotlin.StackOverflowError",
    "java.lang.Class",
]

func runtimeJavaClassDisplayText(receiverRaw: Int, typeToken: Int, nameHint: Int) -> String {
    if let arrayName = runtimeJavaArrayClassName(rawValue: receiverRaw) {
        return "class \(arrayName)"
    }

    let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)

    if let concreteName = runtimeJavaCollectionImplementationName(
        receiverRaw: receiverRaw,
        qualifiedName: qualifiedName
    ) {
        return "class \(concreteName)"
    }

    let binaryName = runtimeJavaBinaryName(qualifiedName, metadataDisplayName: metadata?.displayName)
    let kind = metadata?.isInterface == true ? "interface" : "class"
    return "\(kind) \(binaryName)"
}

func runtimeJavaClassCacheKey(receiverRaw: Int, typeToken: Int, nameHint: Int) -> JavaClassCacheKey {
    if let arrayName = runtimeJavaArrayClassName(rawValue: receiverRaw) {
        let genericArrayToken = runtimeNominalTypeToken(
            runtimeStableNominalTypeID(fqName: "kotlin.Array")
        )
        if typeToken == genericArrayToken {
            return JavaClassCacheKey(typeToken: typeToken, runtimeClassName: arrayName)
        }
    }

    if runtimeListBox(from: receiverRaw) != nil
        || runtimeSetBox(from: receiverRaw) != nil
        || runtimeMapBox(from: receiverRaw) != nil
    {
        let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)
        if let implementationName = runtimeJavaCollectionImplementationName(
            receiverRaw: receiverRaw,
            qualifiedName: qualifiedName
        ) {
            return JavaClassCacheKey(typeToken: typeToken, runtimeClassName: implementationName)
        }
    }

    if let function = runtimeFunctionValueBox(from: receiverRaw) {
        return JavaClassCacheKey(
            typeToken: typeToken,
            functionIdentity: function.fnPtr,
            enclosingClassName: runtimeFunctionEnclosingClassName(for: receiverRaw)
        )
    }

    return JavaClassCacheKey(typeToken: typeToken)
}

func runtimeJavaPrimitiveClassDisplayText(typeToken: Int) -> String {
    return switch Int64(truncatingIfNeeded: typeToken) & RuntimeTypeTokenEncoding.baseMask {
    case RuntimeTypeTokenEncoding.booleanBase: "boolean"
    case RuntimeTypeTokenEncoding.byteBase: "byte"
    case RuntimeTypeTokenEncoding.shortBase: "short"
    case RuntimeTypeTokenEncoding.intBase: "int"
    case RuntimeTypeTokenEncoding.longBase: "long"
    case RuntimeTypeTokenEncoding.charBase: "char"
    case RuntimeTypeTokenEncoding.floatBase: "float"
    case RuntimeTypeTokenEncoding.doubleBase: "double"
    case RuntimeTypeTokenEncoding.nullBase: "void"
    default: "void"
    }
}

func runtimeJavaClassToStringText(_ classRaw: Int) -> String? {
    resolveRuntimeHandle(classRaw, as: RuntimeJavaClassBox.self)?.displayText
}

private func runtimeJavaCollectionImplementationName(receiverRaw: Int, qualifiedName: String) -> String? {
    switch qualifiedName {
    case "kotlin.collections.List", "kotlin.collections.MutableList":
        guard let list = runtimeListBox(from: receiverRaw) else { return nil }
        return switch list.count {
        case 0: "kotlin.collections.EmptyList"
        case 1: "java.util.Collections$SingletonList"
        default: "java.util.Arrays$ArrayList"
        }
    case "kotlin.collections.Set", "kotlin.collections.MutableSet":
        guard let set = runtimeSetBox(from: receiverRaw) else { return nil }
        return switch set.count {
        case 0: "kotlin.collections.EmptySet"
        case 1: "java.util.Collections$SingletonSet"
        default: "java.util.LinkedHashSet"
        }
    case "kotlin.collections.Map", "kotlin.collections.MutableMap":
        guard let map = runtimeMapBox(from: receiverRaw) else { return nil }
        return switch map.count {
        case 0: "kotlin.collections.EmptyMap"
        case 1: "java.util.Collections$SingletonMap"
        default: "java.util.LinkedHashMap"
        }
    case "kotlin.Any", "Unknown":
        if let list = runtimeListBox(from: receiverRaw) {
            return switch list.count {
            case 0: "kotlin.collections.EmptyList"
            case 1: "java.util.Collections$SingletonList"
            default: "java.util.Arrays$ArrayList"
            }
        }
        if let set = runtimeSetBox(from: receiverRaw) {
            return switch set.count {
            case 0: "kotlin.collections.EmptySet"
            case 1: "java.util.Collections$SingletonSet"
            default: "java.util.LinkedHashSet"
            }
        }
        if let map = runtimeMapBox(from: receiverRaw) {
            return switch map.count {
            case 0: "kotlin.collections.EmptyMap"
            case 1: "java.util.Collections$SingletonMap"
            default: "java.util.LinkedHashMap"
            }
        }
        return nil
    default:
        return nil
    }
}

func runtimeJavaQualifiedName(typeToken: Int, nameHint: Int = 0) -> String {
    if let qualifiedName = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)?.qualifiedName {
        return qualifiedName
    }
    if let name = runtimeJavaKnownKotlinNominalNames.first(where: {
        runtimeNominalTypeToken(runtimeStableNominalTypeID(fqName: $0)) == typeToken
    }) {
        return name
    }
    return extractString(from: UnsafeMutableRawPointer(bitPattern: __kk_type_token_qualified_name(typeToken, nameHint)))
        ?? "java.lang.Object"
}

func runtimeJavaBinaryNameForTypeToken(_ typeToken: Int, nameHint: Int = 0) -> String {
    let metadata = runtimeKClassMetadataRegistry.lookup(typeToken: typeToken)
    let qualifiedName = runtimeJavaQualifiedName(typeToken: typeToken, nameHint: nameHint)
    return runtimeJavaBinaryName(qualifiedName, metadataDisplayName: metadata?.displayName)
}

func runtimeJavaBinaryName(_ qualifiedName: String, metadataDisplayName: String?) -> String {
    return switch qualifiedName {
    case "kotlin.Any": "java.lang.Object"
    case "kotlin.String": "java.lang.String"
    case "kotlin.Boolean": "java.lang.Boolean"
    case "kotlin.Byte": "java.lang.Byte"
    case "kotlin.Short": "java.lang.Short"
    case "kotlin.Int": "java.lang.Integer"
    case "kotlin.Long": "java.lang.Long"
    case "kotlin.Char": "java.lang.Character"
    case "kotlin.Float": "java.lang.Float"
    case "kotlin.Double": "java.lang.Double"
    case "kotlin.collections.Collection": "java.util.Collection"
    case "kotlin.collections.List": "java.util.List"
    case "kotlin.collections.MutableList": "java.util.List"
    case "kotlin.collections.Set": "java.util.Set"
    case "kotlin.collections.MutableSet": "java.util.Set"
    case "kotlin.collections.Map": "java.util.Map"
    case "kotlin.collections.MutableMap": "java.util.Map"
    case "kotlin.collections.Map.Entry", "kotlin.collections.MutableMap.MutableEntry": "java.util.Map$Entry"
    case "kotlin.collections.ArrayList": "java.util.ArrayList"
    case "kotlin.collections.HashSet": "java.util.HashSet"
    case "kotlin.collections.LinkedHashSet": "java.util.LinkedHashSet"
    case "kotlin.collections.HashMap": "java.util.HashMap"
    case "kotlin.collections.LinkedHashMap": "java.util.LinkedHashMap"
    case "kotlin.RuntimeException", "kotlin.Exception", "kotlin.IllegalArgumentException",
         "kotlin.IllegalStateException", "kotlin.ArithmeticException", "kotlin.AssertionError",
         "kotlin.ClassCastException", "kotlin.IndexOutOfBoundsException",
         "kotlin.ArrayIndexOutOfBoundsException", "kotlin.StringIndexOutOfBoundsException",
         "kotlin.NegativeArraySizeException", "kotlin.NullPointerException",
         "kotlin.NumberFormatException", "kotlin.UnsupportedOperationException",
         "kotlin.Error", "kotlin.OutOfMemoryError", "kotlin.StackOverflowError":
        runtimeJVMExceptionFQName(from: qualifiedName)
    default:
        metadataDisplayName ?? qualifiedName
    }
}
