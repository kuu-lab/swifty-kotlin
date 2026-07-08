/// String-to-number/boolean parsing functions not already covered by `stringFunctions`.
///
/// `kk_string_toInt`/`toInt_radix`/`toIntOrNull`/`toIntOrNull_radix`/`toUByteOrNull`/
/// `toUShortOrNull`/`toUIntOrNull`/`toULongOrNull` (and their `_radix` variants)/`toDouble`/
/// `toDoubleOrNull`/`toLong`/`toLongOrNull`/`toFloat`/`toFloatOrNull`/`__kk_bignum_toString`
/// are already registered in `RuntimeABISpec+String.swift` (`stringFunctions`); they are
/// intentionally omitted here to avoid duplicate `allFunctions` entries.
public extension RuntimeABISpec {
    static let stringParsingFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_toShortOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-091: String.toByteOrNull()
        RuntimeABIFunctionSpec(
            name: "kk_string_toByteOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-142: String.toBoolean
        RuntimeABIFunctionSpec(
            name: "kk_string_toBoolean",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toBooleanStrict",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toBigDecimal",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_string_toBigDecimalOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]
}
