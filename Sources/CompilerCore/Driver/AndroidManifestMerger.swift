import Foundation

/// Merges library manifests into the app manifest, covering the part of
/// AGP's manifest merger that AndroidX libraries rely on:
///
/// - `${applicationId}` placeholders resolve to the application ID
///   (`androidx.startup` authorities, AndroidX Core's dynamic receiver
///   permission).
/// - Relative component names (`.Foo`) expand against the declaring
///   manifest's package before merging, so they keep their meaning.
/// - Elements match on tag plus `android:name`; matching elements merge
///   their attributes (the app, then earlier libraries, win) and children
///   recursively. This is how several libraries contribute `<meta-data>`
///   to the one `androidx.startup.InitializationProvider`.
/// - `tools:node="remove"` in the app manifest drops the matching library
///   element; other `tools:` markers are stripped from the output.
///
/// `<uses-sdk>` and version attributes come from the build options through
/// aapt2 flags, so library `<uses-sdk>` elements are ignored.
package enum AndroidManifestMerger {
    private static let toolsNamespace = "http://schemas.android.com/tools"
    /// Elements that occur once per parent; they merge with no name.
    private static let singletons: Set<String> = ["application", "queries", "uses-sdk", "supports-screens"]
    /// Attributes holding a class name that may be package-relative.
    private static let classAttributes = ["android:name", "android:targetActivity", "android:backupAgent"]
    private static let componentTags: Set<String> = [
        "activity", "activity-alias", "service", "receiver", "provider", "application", "instrumentation",
    ]

    package static func merge(
        app: AndroidXMLElement,
        namespace: String,
        applicationID: String,
        libraries: [(package: String?, manifest: AndroidXMLElement)]
    ) -> AndroidXMLElement {
        let merged = app.copy()
        if merged[attribute: "package"] == nil { merged[attribute: "package"] = namespace }
        let toolsPrefix = Self.toolsPrefix(of: merged)
        var removals: Set<String> = []
        // Library keys are compared after expansion, so the app's must be too.
        resolve(merged, package: namespace, applicationID: applicationID)
        collectRemovals(merged, toolsPrefix: toolsPrefix, path: "", into: &removals)

        for library in libraries {
            let manifest = library.manifest.copy()
            strip(manifest, toolsPrefix: Self.toolsPrefix(of: manifest))
            resolve(manifest, package: library.package ?? namespace, applicationID: applicationID)
            for child in manifest.children where child.name != "uses-sdk" {
                mergeChild(child, into: merged, path: "", removals: removals)
            }
        }
        strip(merged, toolsPrefix: toolsPrefix)
        return merged
    }

    private static func toolsPrefix(of root: AndroidXMLElement) -> String? {
        root.attributes.first { $0.0.hasPrefix("xmlns:") && $0.1 == toolsNamespace }
            .map { String($0.0.dropFirst("xmlns:".count)) }
    }

    private static func key(_ element: AndroidXMLElement) -> String {
        if singletons.contains(element.name) { return element.name }
        if let name = element[attribute: "android:name"] { return element.name + "|" + name }
        // Nameless elements (`<intent-filter>`, `<data>`) only deduplicate
        // when they are identical.
        return element.name + "|" + element.serialized()
    }

    private static func mergeChild(
        _ child: AndroidXMLElement, into parent: AndroidXMLElement, path: String, removals: Set<String>
    ) {
        let childKey = key(child)
        let childPath = path + "/" + childKey
        guard !removals.contains(childPath) else { return }
        guard let existing = parent.children.first(where: { key($0) == childKey }) else {
            parent.children.append(child)
            return
        }
        for (attribute, value) in child.attributes where existing[attribute: attribute] == nil {
            existing[attribute: attribute] = value
        }
        for grandchild in child.children {
            mergeChild(grandchild, into: existing, path: childPath, removals: removals)
        }
    }

    private static func collectRemovals(
        _ element: AndroidXMLElement, toolsPrefix: String?, path: String, into removals: inout Set<String>
    ) {
        guard let toolsPrefix else { return }
        for child in element.children {
            let childPath = path + "/" + key(child)
            if child[attribute: toolsPrefix + ":node"] == "remove" { removals.insert(childPath) }
            collectRemovals(child, toolsPrefix: toolsPrefix, path: childPath, into: &removals)
        }
        element.children.removeAll { $0[attribute: toolsPrefix + ":node"] == "remove" }
    }

    private static func resolve(_ element: AndroidXMLElement, package: String, applicationID: String) {
        for index in element.attributes.indices {
            var value = element.attributes[index].1
                .replacingOccurrences(of: "${applicationId}", with: applicationID)
            if componentTags.contains(element.name), classAttributes.contains(element.attributes[index].0) {
                if value.hasPrefix(".") {
                    value = package + value
                } else if !value.contains("."), !value.isEmpty {
                    value = package + "." + value
                }
            }
            element.attributes[index].1 = value
        }
        for child in element.children { resolve(child, package: package, applicationID: applicationID) }
    }

    private static func strip(_ element: AndroidXMLElement, toolsPrefix: String?) {
        guard let toolsPrefix else { return }
        element.attributes.removeAll { $0.0.hasPrefix(toolsPrefix + ":") || $0.0 == "xmlns:" + toolsPrefix }
        for child in element.children { strip(child, toolsPrefix: toolsPrefix) }
    }
}
