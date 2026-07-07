import RuntimeABI
import XCTest

// MARK: - Runtime Export / RuntimeABISpec Reconciliation

extension ABIMismatchTests {
    /// The String/Regex/Locale ABI surface is governed by the branch's flat-only
    /// contract, so it is reconciled by the dedicated flat-string tests rather than
    /// the cross-section export/spec parity checks here.
    private func isFlatOnlyExcludedABIName(_ name: String) -> Bool {
        name.hasPrefix("kk_string_")
            || name.hasPrefix("__kk_string_")
            || name.hasPrefix("__string_")
            || name.hasPrefix("kk_regex_")
            || name.hasPrefix("kk_locale_")
    }

    func testRuntimeExportsHaveMatchingRuntimeABISpecEntries() throws {
        let exported = try runtimeExportedABIs()
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let missing = exported.map { $0.name }
            .filter {
                !isFlatOnlyExcludedABIName($0)
                    && !specNames.contains($0)
                    && !allowedRuntimeExportOnlyABINames.contains($0)
            }
            .sorted()

        XCTAssertTrue(
            missing.isEmpty,
            "Runtime exported ABI names missing from RuntimeABISpec: \(missing.joined(separator: ", "))"
        )
    }

    func testRuntimeExportSignaturesMatchRuntimeABISpec() throws {
        let specsByName = Dictionary(uniqueKeysWithValues: RuntimeABISpec.allFunctions.map { ($0.name, $0) })
        for exported in try runtimeExportedABIs() {
            guard !isFlatOnlyExcludedABIName(exported.name) else { continue }
            guard !allowedRuntimeExportOnlyABINames.contains(exported.name) else { continue }
            // Generic functions cannot have their parameter types validated against C ABI types
            guard exported.returnType != "generic" else { continue }
            let spec = try XCTUnwrap(
                specsByName[exported.name],
                "Runtime export '\(exported.name)' from \(exported.source) has no RuntimeABISpec entry"
            )
            XCTAssertEqual(
                spec.returnTypeString,
                exported.returnType,
                "Return type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
            XCTAssertEqual(
                spec.parameterTypeStrings,
                exported.parameterTypes,
                "Parameter type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
        }
    }

    func testSpecOnlyRuntimeABINamesAreExplicitlyAllowed() throws {
        let exportedNames = Set(try runtimeExportedABIs().map { $0.name })
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let unexpected = Set(specNames.filter { !isFlatOnlyExcludedABIName($0) })
            .subtracting(exportedNames)
            .subtracting(allowedSpecOnlyRuntimeABINames)
            .sorted()

        XCTAssertTrue(
            unexpected.isEmpty,
            "RuntimeABISpec entries without Runtime exports must be allowlisted: \(unexpected.joined(separator: ", "))"
        )
    }

    private var allowedRuntimeExportOnlyABINames: Set<String> {
        [
            "kk_kclass_nested_classes",
            "kk_regex_create_with_option",
            "kk_regex_create_with_options",
            "kk_string_chunked_sequence",
            "kk_string_chunked_sequence_transform",
            "kk_string_replace",
            "kk_string_replaceIndentByMargin",
            "kk_string_toByte",
            "kk_string_toByte_radix",
            "kk_string_toCharArray",
            "kk_string_toRegex_with_option",
            "kk_string_toRegex_with_options",
            "kk_string_toShort",
            "kk_string_windowed",
            "kk_string_windowed_default",
            "kk_string_windowed_partial",
            "kk_string_windowedSequence_partial",
            "kk_string_windowedSequence_transform",
        ]
    }

    private var allowedSpecOnlyRuntimeABINames: Set<String> {
        [
            "kk_annotation_class_name",
            "kk_annotation_get_arguments",
            "kk_annotation_simple_class_name",
            "kk_any_javaClass",
            "kk_array_isArrayOf",
            "kk_callable_ref_call_0",
            "kk_callable_ref_call_1",
            "kk_callable_ref_call_2",
            "kk_callable_ref_call_3",
            "kk_callback_flow_await_close",
            "kk_callback_flow_create",
            "kk_channel_flow_create",
            "kk_channel_flow_send",
            "kk_channel_flow_try_send",
            "kk_channel_send_suspending",
            "kk_flow_catch",
            "kk_flow_on_completion",
            "kk_flow_on_error_resume",
            "kk_flow_on_error_return",
            "kk_flow_retry",
            "kk_flow_retry_when",
            "kk_hexformat_prefix",
            "kk_hexformat_suffix",
            "kk_math_e",
            "kk_math_pi",
            "kk_mem_scope_alloc",
            "kk_mem_scope_enter",
            "kk_mem_scope_exit",
            "kk_native_alloc_bytes",
            "kk_char_sequence_length",
            "kk_dynamic_iterator",
            "kk_future_getState",
            "kk_int_to_int",
            "kk_js_number_toDouble",
            "kk_js_number_toInt",
            "kk_kclass_has_annotation",
            "kk_kclass_js",
            "kk_kclass_register_annotation",
            "kk_long_range_firstOrNull",
            "kk_long_range_lastOrNull",
            "kk_native_atomic_ref_compareAndSet",
            "kk_native_atomic_ref_compareAndSwap",
            "kk_native_atomic_ref_create",
            "kk_native_atomic_ref_load",
            "kk_path_createLinkPointingTo",
            "kk_path_deleteExisting",
            "kk_path_deleteRecursively",
            "kk_path_div_path",
            "kk_path_div_string",
            "kk_path_fileAttributesView",
            "kk_path_fileAttributesViewOrNull",
            "kk_path_fileSize",
            "kk_path_fileStore",
            "kk_path_fileAttributesView",

            "kk_path_getAttribute",
            "kk_path_getPosixFilePermissions",
            "kk_path_get_base_subpaths",
            "kk_path_isExecutable",
            "kk_path_isHidden",
            "kk_path_isReadable",
            "kk_path_isSameFileAs",
            "kk_path_isSymbolicLink",
            "kk_path_isWritable",
            "kk_path_moveTo_options",
            "kk_path_moveTo_overwrite",
            "kk_path_outputStream",
            "kk_path_inputStream",
            "kk_path_readAttributes",
            "kk_path_readBytes",
            "kk_path_readLines_charset",
            "kk_path_readSymbolicLink",
            "kk_path_readText_charset",
            "kk_path_relativeTo",
            "kk_path_relativeToOrNull",
            "kk_path_relativeToOrSelf",
            "kk_path_setAttribute",
            "kk_path_setOwner",
            "kk_path_setPosixFilePermissions",
            "kk_path_writeBytes",
            "kk_path_writeLines_iterable",
            "kk_path_writeLines_sequence",
            "kk_path_reader",
            "kk_path_reader_default",
            "kk_path_readAttributes_string",
            "kk_path_writeText_options",
            "kk_uri_toPath",
        ]
    }

    private struct RuntimeExportedABI {
        let name: String
        let returnType: String
        let parameterTypes: [String]
        let source: String
    }

    private enum RuntimeExportParseError: Error, CustomStringConvertible {
        case missingParameterType(String, source: String)
        case unknownSwiftType(String, source: String)

        var description: String {
            switch self {
            case let .missingParameterType(parameter, source):
                "Runtime export parameter is missing a type in \(source): \(parameter)"
            case let .unknownSwiftType(type, source):
                "Runtime export uses an unmapped Swift ABI type in \(source): \(type)"
            }
        }
    }

    private func runtimeExportedABIs() throws -> [RuntimeExportedABI] {
        let root = packageRootForRuntimeTests().appendingPathComponent("Sources/Runtime")
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var exports: [RuntimeExportedABI] = []
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            let resourceValues = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard resourceValues.isRegularFile == true else { continue }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let relativePath = fileURL.path.replacingOccurrences(
                of: packageRootForRuntimeTests().path + "/",
                with: ""
            )
            exports.append(contentsOf: try runtimeExportedABIs(in: source, sourcePath: relativePath))
        }
        return exports.sorted { $0.name < $1.name }
    }

    private func runtimeExportedABIs(in source: String, sourcePath: String) throws -> [RuntimeExportedABI] {
        let concretePatterns = [
            #"@_cdecl\("([^"]+)"\)\s*(?:public\s+)?func\s+[A-Za-z0-9_]+\s*\((.*?)\)\s*(?:->\s*([^{\n]+))?"#,
            #"@_silgen_name\("([^"]+)"\)\s*public\s+func\s+[A-Za-z0-9_]+\s*\((.*?)\)\s*(?:->\s*([^{\n]+))?"#,
        ]
        let genericPattern = #"@_silgen_name\("([^"]+)"\)\s*public\s+func\s+[A-Za-z0-9_]+<[^>]+>"#

        var exports: [RuntimeExportedABI] = []

        // Collect generic-function names first (name-only; signature cannot be mapped to C types)
        let genericRegex = try NSRegularExpression(pattern: genericPattern, options: [])
        let fullRange = NSRange(source.startIndex..<source.endIndex, in: source)
        var genericNames: Set<String> = []
        for match in genericRegex.matches(in: source, range: fullRange) {
            guard let nameRange = Range(match.range(at: 1), in: source) else { continue }
            genericNames.insert(String(source[nameRange]))
        }
        for name in genericNames {
            exports.append(RuntimeExportedABI(name: name, returnType: "generic", parameterTypes: [], source: sourcePath))
        }

        for pattern in concretePatterns {
            let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in regex.matches(in: source, range: range) {
                guard
                    let nameRange = Range(match.range(at: 1), in: source),
                    let paramsRange = Range(match.range(at: 2), in: source)
                else {
                    continue
                }
                let name = String(source[nameRange])
                guard !genericNames.contains(name) else { continue }
                let params = String(source[paramsRange])
                let returnType: String
                if match.range(at: 3).location == NSNotFound {
                    returnType = RuntimeABICType.void.rawValue
                } else if let returnRange = Range(match.range(at: 3), in: source) {
                    returnType = try cTypeString(
                        forSwiftType: normalizedSwiftType(String(source[returnRange])),
                        source: sourcePath
                    )
                } else {
                    returnType = RuntimeABICType.void.rawValue
                }

                exports.append(RuntimeExportedABI(
                    name: name,
                    returnType: returnType,
                    parameterTypes: try parameterCTypeStrings(params, exportName: name, source: sourcePath),
                    source: sourcePath
                ))
            }
        }
        return exports
    }

    private func parameterCTypeStrings(
        _ parameters: String,
        exportName: String,
        source: String
    ) throws -> [String] {
        let trimmed = parameters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        return try trimmed.split(separator: ",").enumerated().map { index, rawParameter in
            let parameter = String(rawParameter).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = parameter.firstIndex(of: ":") else {
                throw RuntimeExportParseError.missingParameterType(parameter, source: source)
            }
            let typeStart = parameter.index(after: colonIndex)
            let swiftType = normalizedSwiftType(String(parameter[typeStart...]))
            if exportName == "kk_alloc", index == 1, swiftType == "UnsafeRawPointer" {
                return RuntimeABICType.constTypeInfoPointer.rawValue
            }
            return try cTypeString(forSwiftType: swiftType, source: source)
        }
    }

    private func normalizedSwiftType(_ type: String) -> String {
        let withoutDefault = type.split(separator: "=", maxSplits: 1).first.map(String.init) ?? type
        return withoutDefault
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cTypeString(forSwiftType swiftType: String, source: String) throws -> String {
        switch swiftType {
        case "Void":
            RuntimeABICType.void.rawValue
        case "Never":
            RuntimeABICType.noreturn.rawValue
        case "Int":
            RuntimeABICType.intptr.rawValue
        case "Int32":
            RuntimeABICType.int32.rawValue
        case "UInt32":
            RuntimeABICType.uint32.rawValue
        case "UInt64":
            RuntimeABICType.uint64.rawValue
        case "Int64":
            RuntimeABICType.int64.rawValue
        case "Float":
            RuntimeABICType.float.rawValue
        case "Double":
            RuntimeABICType.double.rawValue
        case "UnsafeMutableRawPointer":
            RuntimeABICType.opaquePointer.rawValue
        case "UnsafeMutableRawPointer?":
            RuntimeABICType.nullableOpaquePointer.rawValue
        case "UnsafeRawPointer":
            RuntimeABICType.constRawPointer.rawValue
        case "UnsafeRawPointer?":
            RuntimeABICType.nullableConstRawPointer.rawValue
        case "UnsafePointer<KTypeInfo>":
            RuntimeABICType.constTypeInfoPointer.rawValue
        case "UnsafePointer<UInt8>":
            RuntimeABICType.constUInt8Pointer.rawValue
        case "UnsafePointer<UInt8>?":
            RuntimeABICType.nullableConstUInt8Pointer.rawValue
        case "UnsafeMutablePointer<UInt8>?":
            RuntimeABICType.nullableUInt8Pointer.rawValue
        case "UnsafeMutablePointer<Int>?":
            RuntimeABICType.nullableIntptrPointer.rawValue
        case "UnsafeMutablePointer<UnsafeMutableRawPointer?>?":
            RuntimeABICType.nullableRawPointerPointer.rawValue
        default:
            throw RuntimeExportParseError.unknownSwiftType(swiftType, source: source)
        }
    }

    private func packageRootForRuntimeTests(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
