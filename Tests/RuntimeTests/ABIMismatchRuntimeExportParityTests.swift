#if canImport(Testing)
import Foundation
import RuntimeABI
import Testing

// MARK: - Runtime Export / RuntimeABISpec Reconciliation

@Suite
struct ABIMismatchRuntimeExportParityTests {
    private typealias Symbol = RuntimeABISpecTestSymbol

    /// The String/Regex/Locale ABI surface is governed by the branch's flat-only
    /// contract, so it is reconciled by the dedicated flat-string tests rather than
    /// the cross-section export/spec parity checks here.
    private func isFlatOnlyExcludedABIName(_ name: String) -> Bool {
        Symbol.matchesFamily(.string, namespace: .runtime, name: name)
            || Symbol.matchesFamily(.string, namespace: .bridge, name: name)
            || Symbol.matchesFamily(.regex, namespace: .runtime, name: name)
            || Symbol.matchesFamily(.locale, namespace: .runtime, name: name)
    }

    @Test
    func testRuntimeExportsHaveMatchingRuntimeABISpecEntries() throws {
        let exported = try runtimeExportedABIs()
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let missing = exported.map { $0.name }
            .filter {
                !isFlatOnlyExcludedABIName($0)
                    && !specNames.contains($0)
            }
            .sorted()

        #expect(
            missing.isEmpty,
            "Runtime exported ABI names missing from RuntimeABISpec: \(missing.joined(separator: ", "))"
        )
    }

    @Test
    func testRuntimeExportSignaturesMatchRuntimeABISpec() throws {
        let specsByName = Dictionary(uniqueKeysWithValues: RuntimeABISpec.allFunctions.map { ($0.name, $0) })
        for exported in try runtimeExportedABIs() {
            guard !isFlatOnlyExcludedABIName(exported.name) else { continue }
            // Generic functions cannot have their parameter types validated against C ABI types
            guard exported.returnType != "generic" else { continue }
            let spec = try #require(
                specsByName[exported.name],
                "Runtime export '\(exported.name)' from \(exported.source) has no RuntimeABISpec entry"
            )
            #expect(
                spec.returnTypeString == exported.returnType,
                "Return type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
            #expect(
                spec.parameterTypeStrings == exported.parameterTypes,
                "Parameter type mismatch for runtime export '\(exported.name)' from \(exported.source)"
            )
        }
    }

    @Test
    func testSchedulerClockUsesWordABI() throws {
        for name in [RuntimeABISpec.testScopeCurrentTimeSpec, RuntimeABISpec.testSchedulerCurrentTimeSpec] {
            let spec = try name.requireRegistration()
            #expect(spec.returnType == .intptr)
            #expect(spec.parameters.map(\.type) == [.intptr])
        }
        let advance = try RuntimeABISpec.testSchedulerAdvanceTimeBySpec.requireRegistration()
        #expect(advance.parameters.map(\.type) == [.intptr, .intptr])
    }

    @Test
    func testMigratedBridgeExportsPreserveThrowingChannelContract() throws {
        let expected: [(spec: RuntimeABIFunctionSpec, isThrowing: Bool)] = [
            (RuntimeABISpec.durationParseSpec, true),
            (RuntimeABISpec.durationParseOrNullSpec, false),
            (RuntimeABISpec.durationParseIsoStringSpec, true),
            (RuntimeABISpec.durationParseIsoStringOrNullSpec, false),
            (RuntimeABISpec.sequenceFilterNotSpec, false),
            (RuntimeABISpec.sequenceContainsSpec, false),
            (RuntimeABISpec.sequenceElementAtOrNullSpec, false),
            (RuntimeABISpec.bridgeMutableListAddSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionAddSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionRemoveSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionClearSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionAddAllSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionRemoveAllSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionRetainAllSpec, false),
            (RuntimeABISpec.bridgeMutableCollectionAddThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionRemoveThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionClearThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionAddAllThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionRemoveAllThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableCollectionRetainAllThrowingSpec, true),
            (RuntimeABISpec.bridgeMutableSetAddSpec, true),
            (RuntimeABISpec.bridgeMutableSetRemoveSpec, true),
            (RuntimeABISpec.bridgeMutableMapPutSpec, true),
            (RuntimeABISpec.bridgeMutableMapRemoveSpec, true),
            (RuntimeABISpec.bridgeMutableMapClearSpec, true),
        ]
        let exportsByName = Dictionary(grouping: try runtimeExportedABIs(), by: \.name)

        for item in expected {
            let spec = try item.spec.requireRegistration()
            let export = try #require(exportsByName[spec.name]?.first, "Missing runtime export \(spec.name)")
            let exportHasThrownChannel = export.parameterTypes.last == RuntimeABICType.nullableIntptrPointer.rawValue
            #expect(spec.isThrowing == item.isThrowing)
            #expect(
                exportHasThrownChannel == item.isThrowing,
                "Runtime export \(spec.name) has the wrong throwing channel"
            )
            #expect(
                spec.parameters.map(\.type.rawValue) == export.parameterTypes,
                "Runtime export \(spec.name) parameter types must match RuntimeABISpec"
            )
            #expect(
                spec.returnType.rawValue == export.returnType,
                "Runtime export \(spec.name) return type must match RuntimeABISpec"
            )
        }
    }

    @Test
    func testSpecOnlyRuntimeABINamesAreExplicitlyAllowed() throws {
        let exportedNames = Set(try runtimeExportedABIs().map { $0.name })
        let specNames = Set(RuntimeABISpec.allFunctions.map { $0.name })
        let unexpected = Set(specNames.filter { !isFlatOnlyExcludedABIName($0) })
            .subtracting(exportedNames)
            .subtracting(try allowedSpecOnlyRuntimeABINames())
            .sorted()

        #expect(
            unexpected.isEmpty,
            "RuntimeABISpec entries without Runtime exports must be allowlisted: \(unexpected.joined(separator: ", "))"
        )
    }

    private func allowedSpecOnlyRuntimeABINames() throws -> Set<String> {
        let canonicalSpecs: [RuntimeABIFunctionSpec] = [
            RuntimeABISpec.callableRefCall0Spec,
            RuntimeABISpec.callableRefCall1Spec,
            RuntimeABISpec.callableRefCall2Spec,
            RuntimeABISpec.callableRefCall3Spec,
            RuntimeABISpec.channelSendSuspendingSpec,
            RuntimeABISpec.flowCatchSpec,
            RuntimeABISpec.flowOnCompletionSpec,
            RuntimeABISpec.flowOnErrorResumeSpec,
            RuntimeABISpec.flowOnErrorReturnSpec,
            RuntimeABISpec.flowRetrySpec,
            RuntimeABISpec.flowRetryWhenSpec,
            RuntimeABISpec.mathESpec,
            RuntimeABISpec.mathPiSpec,
            RuntimeABISpec.memScopeAllocSpec,
            RuntimeABISpec.memScopeEnterSpec,
            RuntimeABISpec.memScopeExitSpec,
            RuntimeABISpec.nativeAllocBytesSpec,
            RuntimeABISpec.charSequenceLengthSpec,
            RuntimeABISpec.dynamicIteratorSpec,
            RuntimeABISpec.intToIntSpec,
            // KSP-426: source-backed in ListSortingHOF.kt / ListExtremaHOF.kt;
            // retained only in RuntimeABISpec and test-only compatibility shims.
            RuntimeABISpec.listMaxSpec,
            RuntimeABISpec.listMaxOrNullSpec,
            RuntimeABISpec.listMinSpec,
            RuntimeABISpec.listMinOrNullSpec,
            RuntimeABISpec.listMaxBySpec,
            RuntimeABISpec.listMaxByOrNullSpec,
            RuntimeABISpec.listMinBySpec,
            RuntimeABISpec.listMinByOrNullSpec,
            RuntimeABISpec.listMaxOfSpec,
            RuntimeABISpec.listMaxOfOrNullSpec,
            RuntimeABISpec.listMinOfSpec,
            RuntimeABISpec.listMinOfOrNullSpec,
            RuntimeABISpec.listMaxOfWithSpec,
            RuntimeABISpec.listMaxOfWithOrNullSpec,
            RuntimeABISpec.listMinOfWithSpec,
            RuntimeABISpec.listMinOfWithOrNullSpec,
            RuntimeABISpec.listMaxWithSpec,
            RuntimeABISpec.listMaxWithOrNullSpec,
            RuntimeABISpec.listMinWithSpec,
            RuntimeABISpec.listMinWithOrNullSpec,
            RuntimeABISpec.listSortedSpec,
            RuntimeABISpec.listSortedDescendingSpec,
            RuntimeABISpec.listSortedWithSpec,
            RuntimeABISpec.listSortedPrimitiveSpec,
            RuntimeABISpec.listSortedDescendingPrimitiveSpec,
            RuntimeABISpec.listSortedBySpec,
            RuntimeABISpec.listSortedByDescendingSpec,
            RuntimeABISpec.listSortedByPrimitiveSpec,
            RuntimeABISpec.listSortedByDescendingPrimitiveSpec,
            // KSP-1511: shuffled/shuffled(Random) source-backed in
            // ListSortingHOF.kt; retained only in RuntimeABISpec (same
            // treatment as the KSP-426 block above).
            RuntimeABISpec.listShuffledSpec,
            RuntimeABISpec.listShuffledRandomSpec,
            RuntimeABISpec.listZipTransformSpec,
            // KSP-688: List slice/take/drop HOFs are source-backed in
            // kotlin.collections.ListSliceTakeDrop.kt; their compatibility
            // ABI specs remain but no runtime exports are emitted.
            RuntimeABISpec.listTakeWhileSpec,
            RuntimeABISpec.listTakeLastWhileSpec,
            RuntimeABISpec.listDropWhileSpec,
            RuntimeABISpec.listDropLastWhileSpec,
            // KSP-445: Sequence scan HOFs are source-backed in bundled
            // kotlin.collections/sequences; runtime bridges are no longer exported.
            RuntimeABISpec.sequenceReduceIndexedSpec,
            RuntimeABISpec.sequenceReduceIndexedOrNullSpec,
            RuntimeABISpec.sequenceRunningFoldSpec,
            RuntimeABISpec.sequenceRunningFoldIndexedSpec,
            RuntimeABISpec.sequenceRunningReduceSpec,
            RuntimeABISpec.sequenceRunningReduceIndexedSpec,
            RuntimeABISpec.sequenceScanSpec,
            RuntimeABISpec.sequenceScanIndexedSpec,
            // KSP-430: Map higher-order functions are now source-backed in
            // bundled MapHOF.kt. RF-LOWER-CALL-012 removed the Lowering-side
            // rewrites and KSP-703 removed the Sema-side synthetic stub
            // registrations that used to reference these names — no
            // `@_cdecl` and no compiler-side reference remain for any of
            // them — but the `RuntimeABISpec` entries themselves stay
            // allowed here pending a decision on pruning the spec.
            RuntimeABISpec.mapAllSpec,
            RuntimeABISpec.mapAnySpec,
            RuntimeABISpec.mapCountSpec,
            RuntimeABISpec.mapNoneSpec,
            RuntimeABISpec.mapFilterSpec,
            RuntimeABISpec.mapFilterKeysSpec,
            RuntimeABISpec.mapFilterNotSpec,
            RuntimeABISpec.mapFilterValuesSpec,
            RuntimeABISpec.mapFlatMapSpec,
            RuntimeABISpec.mapForEachSpec,
            RuntimeABISpec.mapMapSpec,
            RuntimeABISpec.mapMapNotNullSpec,
            RuntimeABISpec.mapMapKeysSpec,
            RuntimeABISpec.mapMapKeysToSpec,
            RuntimeABISpec.mapMapValuesSpec,
            RuntimeABISpec.mapMapValuesToSpec,
            RuntimeABISpec.mapMaxByOrNullSpec,
            RuntimeABISpec.mapMinByOrNullSpec,
            RuntimeABISpec.mapMinusSpec,
            RuntimeABISpec.mapPlusSpec,
        ]
        return Set(try canonicalSpecs.map { try $0.requireRegistration().name })
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
            if exportName == RuntimeABISpec.allocSpec.name, index == 1, swiftType == "UnsafeRawPointer" {
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
#endif
