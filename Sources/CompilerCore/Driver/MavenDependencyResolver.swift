import Foundation

/// One artifact file of the resolved runtime classpath.
package struct MavenResolvedArtifact: Equatable, Sendable {
    package let coordinate: MavenCoordinate
    package let file: URL
}

/// Resolves `--android-dependency` coordinates to the files an Android
/// app packages, the way Gradle resolves `debugRuntimeClasspath`:
///
/// - Gradle Module Metadata (`.module`) is preferred; its Android/JVM
///   runtime variant selects files and dependencies, and `available-at`
///   redirects Kotlin Multiplatform roots (`androidx.compose.ui:ui`) to
///   their Android publication (`ui-android`). Artifacts without metadata
///   fall back to the POM (`compile` and `runtime` scopes).
/// - Conflicts resolve to the newest requested version (Gradle's default),
///   and `dependencyConstraints` raise versions of modules already in the
///   graph. Resolution repeats until the selection stops changing, so an
///   edge contributed only by a version that lost a conflict is dropped.
/// - The Kotlin standard library modules are excluded: the kswiftc runtime
///   (`-include-runtime` or `kswiftc --stdlib-only`) replaces them.
///
/// Per-dependency `excludes` and version ranges beyond a single pinned
/// version (`[1.2]`) are not modelled.
package final class MavenDependencyResolver {
    package static let excludedModules: Set<MavenModuleID> = [
        "kotlin-stdlib", "kotlin-stdlib-common", "kotlin-stdlib-jdk7", "kotlin-stdlib-jdk8", "kotlin-reflect",
    ].reduce(into: []) { $0.insert(MavenModuleID(group: "org.jetbrains.kotlin", artifact: $1)) }

    private let repositories: MavenRepositorySet
    private var descriptors: [MavenCoordinate: Descriptor] = [:]

    package init(repositories: MavenRepositorySet) {
        self.repositories = repositories
    }

    package func resolve(_ roots: [MavenCoordinate]) throws -> [MavenResolvedArtifact] {
        for root in roots {
            _ = try Self.coordinate(group: root.module.group, artifact: root.module.artifact, version: root.version)
        }
        var selected: [MavenModuleID: String] = [:]
        for iteration in 0... {
            let (order, requests, failures) = try traverse(roots: roots, selected: selected)
            var next: [MavenModuleID: String] = [:]
            for module in order {
                guard let versions = requests[module] else { continue }
                next[module] = versions.strict ?? versions.newest
            }
            // Selections only move when an upgrade changes the edge set; a
            // graph that keeps flipping is accepted as-is after the cap.
            if next == selected || iteration == 32 {
                selected = next
                // Metadata of a version that lost a conflict may be missing;
                // only a failure of a version that stays selected is fatal.
                for module in order {
                    if let failure = failures[module], failure.version == selected[module] { throw failure.error }
                }
                var artifacts: [MavenResolvedArtifact] = []
                for module in order {
                    guard let version = selected[module] else { continue }
                    let coordinate = MavenCoordinate(module: module, version: version)
                    for file in try descriptor(coordinate).files {
                        artifacts.append(MavenResolvedArtifact(
                            coordinate: coordinate,
                            file: try repositories.require(coordinate, suffix: file)
                        ))
                    }
                }
                return artifacts
            }
            selected = next
        }
        preconditionFailure("unbounded range loop exited")
    }

    private struct Requests {
        var newest: String
        var strict: String?

        mutating func add(_ version: String, strict isStrict: Bool) {
            if MavenVersion.isNewer(version, than: newest) { newest = version }
            if isStrict, strict.map({ MavenVersion.isNewer(version, than: $0) }) ?? true { strict = version }
        }
    }

    /// Breadth-first walk over the graph implied by `selected` (falling back
    /// to the first requested version for modules not yet selected).
    private func traverse(
        roots: [MavenCoordinate], selected: [MavenModuleID: String]
    ) throws -> ([MavenModuleID], [MavenModuleID: Requests], [MavenModuleID: (version: String, error: Error)]) {
        var failures: [MavenModuleID: (version: String, error: Error)] = [:]
        var requests: [MavenModuleID: Requests] = [:]
        var order: [MavenModuleID] = []
        var queue: [MavenModuleID] = []
        // Constraints only align modules something else brings in, whether
        // that happens before or after the constraint is seen.
        var constraints: [MavenModuleID: [String]] = [:]
        func request(_ module: MavenModuleID, _ version: String, strict: Bool) {
            guard !Self.excludedModules.contains(module) else { return }
            if requests[module] == nil {
                requests[module] = Requests(newest: version, strict: strict ? version : nil)
                for constrained in constraints[module] ?? [] { requests[module]?.add(constrained, strict: false) }
                order.append(module)
                queue.append(module)
            } else {
                requests[module]?.add(version, strict: strict)
            }
        }
        for root in roots { request(root.module, root.version, strict: false) }
        var index = 0
        while index < queue.count {
            let module = queue[index]
            index += 1
            guard let version = selected[module] ?? requests[module]?.newest else { continue }
            let node: Descriptor
            do {
                node = try descriptor(MavenCoordinate(module: module, version: version))
            } catch {
                failures[module] = (version, error)
                continue
            }
            for constraint in node.constraints {
                constraints[constraint.module, default: []].append(constraint.version)
                requests[constraint.module]?.add(constraint.version, strict: false)
            }
            for dependency in node.dependencies {
                request(dependency.module, dependency.version, strict: dependency.strict)
            }
        }
        return (order, requests, failures)
    }

    // MARK: - Metadata

    private struct Dependency {
        let module: MavenModuleID
        let version: String
        let strict: Bool
    }

    private struct Descriptor {
        var dependencies: [Dependency] = []
        var constraints: [Dependency] = []
        var files: [String] = []
    }

    private func descriptor(_ coordinate: MavenCoordinate) throws -> Descriptor {
        if let cached = descriptors[coordinate] { return cached }
        let result: Descriptor
        if let module = try repositories.fetch(coordinate, suffix: ".module") {
            result = try moduleDescriptor(coordinate, file: module)
        } else {
            result = try pomDescriptor(coordinate)
        }
        descriptors[coordinate] = result
        return result
    }

    /// Gradle Module Metadata 1.x.
    private func moduleDescriptor(_ coordinate: MavenCoordinate, file: URL) throws -> Descriptor {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
        } catch {
            throw MavenResolutionError.metadata(coordinate.description, detail: "\(error)")
        }
        guard let root = object as? [String: Any], let variants = root["variants"] as? [[String: Any]] else {
            throw MavenResolutionError.metadata(coordinate.description, detail: "no variants")
        }
        guard let variant = variants.compactMap({ v in Self.runtimeScore(v).map { (v, $0) } })
            .max(by: { $0.1 < $1.1 })?.0
        else {
            throw MavenResolutionError.metadata(
                coordinate.description, detail: "no Android or JVM runtime variant"
            )
        }
        var descriptor = Descriptor()
        if let redirect = variant["available-at"] as? [String: Any],
           let group = redirect["group"] as? String, let artifact = redirect["module"] as? String,
           let version = redirect["version"] as? String {
            let target = try Self.coordinate(group: group, artifact: artifact, version: version)
            descriptor.dependencies.append(Dependency(module: target.module, version: target.version, strict: false))
            return descriptor
        }
        func dependencies(_ key: String) throws -> [Dependency] {
            try (variant[key] as? [[String: Any]] ?? []).compactMap { entry in
                guard let group = entry["group"] as? String, let artifact = entry["module"] as? String,
                      let version = entry["version"] as? [String: Any] else { return nil }
                let strictly = version["strictly"] as? String
                guard let value = strictly ?? version["requires"] as? String ?? version["prefers"] as? String
                else { return nil }
                let target = try Self.coordinate(group: group, artifact: artifact, version: value)
                return Dependency(module: target.module, version: target.version, strict: strictly != nil)
            }
        }
        descriptor.dependencies = try dependencies("dependencies")
        descriptor.constraints = try dependencies("dependencyConstraints")
        descriptor.files = (variant["files"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let url = entry["url"] as? String,
                  url.hasPrefix(coordinate.module.artifact + "-" + coordinate.version) else {
                // Files outside the `<artifact>-<version>` naming would need
                // per-file cache paths; AndroidX and kotlinx do not use them.
                return nil
            }
            let suffix = String(url.dropFirst(coordinate.module.artifact.count + coordinate.version.count + 1))
            // The suffix names a cache file: it must stay in the version directory.
            guard !suffix.contains("/"), !suffix.contains("\\"), !suffix.contains("..") else { return nil }
            return suffix
        }
        return descriptor
    }

    /// Higher is better; nil means the variant is not a runtime library.
    private static func runtimeScore(_ variant: [String: Any]) -> Int? {
        let attributes = variant["attributes"] as? [String: Any] ?? [:]
        func value(_ key: String) -> String? { attributes[key] as? String }
        guard value("org.gradle.category") ?? "library" == "library",
              value("org.gradle.usage") == "java-runtime" else { return nil }
        var score = 0
        switch value("org.jetbrains.kotlin.platform.type") {
        case "androidJvm": score += 4
        case "jvm": score += 2
        case nil: score += 1
        default: return nil
        }
        switch value("org.gradle.jvm.environment") {
        case "android": score += 2
        case "standard-jvm": score -= 1
        default: break
        }
        if value("org.gradle.libraryelements") ?? "jar" != "jar" && value("org.gradle.libraryelements") != "aar" {
            return nil
        }
        return score
    }

    /// Maven POM 4.0.0, including parent inheritance of properties and
    /// `dependencyManagement` versions.
    private func pomDescriptor(_ coordinate: MavenCoordinate) throws -> Descriptor {
        let pom = try loadPOM(coordinate)
        var descriptor = Descriptor()
        let packaging = pom.packaging
        if packaging != "pom" {
            descriptor.files = [packaging == "aar" ? ".aar" : ".jar"]
        }
        for dependency in pom.dependencies {
            let scope = dependency.value("scope") ?? "compile"
            guard scope == "compile" || scope == "runtime", dependency.value("optional") != "true",
                  let group = dependency.value("groupId").map(pom.expand),
                  let artifact = dependency.value("artifactId").map(pom.expand) else { continue }
            let module = try Self.coordinate(group: group, artifact: artifact, version: "0").module
            guard let rawVersion = dependency.value("version").map(pom.expand) ?? pom.managedVersions[module]
            else {
                throw MavenResolutionError.metadata(
                    coordinate.description, detail: "dependency \(module) has no version"
                )
            }
            let pinned = rawVersion.hasPrefix("[") && rawVersion.hasSuffix("]") && !rawVersion.contains(",")
            let version = rawVersion.trimmingCharacters(in: CharacterSet(charactersIn: "[]()"))
                .split(separator: ",").first.map(String.init) ?? rawVersion
            _ = try Self.coordinate(group: group, artifact: artifact, version: version)
            descriptor.dependencies.append(Dependency(module: module, version: version, strict: pinned))
        }
        return descriptor
    }

    private struct POM {
        let root: AndroidXMLElement
        var properties: [String: String]
        var managedVersions: [MavenModuleID: String]
        /// `<dependency>` elements, inherited from parents unless redeclared.
        var dependencies: [AndroidXMLElement] = []

        func key(_ dependency: AndroidXMLElement) -> MavenModuleID? {
            guard let group = dependency.value("groupId").map(expand),
                  let artifact = dependency.value("artifactId").map(expand) else { return nil }
            return MavenModuleID(group: group, artifact: artifact)
        }

        var packaging: String { root.value("packaging").map(expand) ?? "jar" }

        func expand(_ text: String) -> String {
            var result = text
            for _ in 0..<8 {
                guard let start = result.range(of: "${"),
                      let end = result.range(of: "}", range: start.upperBound..<result.endIndex) else { break }
                let key = String(result[start.upperBound..<end.lowerBound])
                guard let value = properties[key] else { break }
                result.replaceSubrange(start.lowerBound..<end.upperBound, with: value)
            }
            return result
        }
    }

    private func loadPOM(_ coordinate: MavenCoordinate, visiting: Set<MavenCoordinate> = []) throws -> POM {
        guard !visiting.contains(coordinate), visiting.count < 16 else {
            throw MavenResolutionError.metadata(coordinate.description, detail: "cyclic or too deep parent/BOM chain")
        }
        let visiting = visiting.union([coordinate])
        let file = try repositories.require(coordinate, suffix: ".pom")
        let root: AndroidXMLElement
        do {
            root = try AndroidXMLElement.parse(Data(contentsOf: file))
        } catch {
            throw MavenResolutionError.metadata(coordinate.description, detail: "\(error)")
        }
        var pom = POM(root: root, properties: [:], managedVersions: [:])
        if let parent = root.child("parent"),
           let group = parent.value("groupId"), let artifact = parent.value("artifactId"),
           let version = parent.value("version") {
            let inherited = try loadPOM(
                try Self.coordinate(group: group, artifact: artifact, version: version),
                visiting: visiting
            )
            pom.properties = inherited.properties
            pom.managedVersions = inherited.managedVersions
            pom.dependencies = inherited.dependencies
        }
        for property in root.child("properties")?.children ?? [] {
            pom.properties[property.localName] = property.text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let group = root.value("groupId") ?? root.child("parent")?.value("groupId") ?? coordinate.module.group
        let version = root.value("version") ?? root.child("parent")?.value("version") ?? coordinate.version
        for (key, value) in [
            ("project.groupId", group), ("pom.groupId", group), ("groupId", group),
            ("project.version", version), ("pom.version", version), ("version", version),
            ("project.artifactId", coordinate.module.artifact),
        ] {
            pom.properties[key] = value
        }
        // Versions this POM manages explicitly win over imported BOMs; among
        // BOMs the first import wins, as in Maven.
        var imports: [MavenCoordinate] = []
        for managed in root.child("dependencyManagement")?.child("dependencies")?.children("dependency") ?? [] {
            guard let module = pom.key(managed), let version = managed.value("version").map(pom.expand) else { continue }
            if managed.value("type") == "pom", managed.value("scope") == "import" {
                imports.append(try Self.coordinate(group: module.group, artifact: module.artifact, version: version))
            } else {
                pom.managedVersions[module] = version
            }
        }
        let explicit = Set(pom.managedVersions.keys)
        var imported: [MavenModuleID: String] = [:]
        for bom in imports {
            for (module, version) in try loadPOM(bom, visiting: visiting).managedVersions
                where imported[module] == nil && !explicit.contains(module) {
                imported[module] = version
            }
        }
        pom.managedVersions.merge(imported) { current, _ in current }
        var dependencies = pom.dependencies
        for dependency in root.child("dependencies")?.children("dependency") ?? [] {
            let key = pom.key(dependency)
            dependencies.removeAll { key != nil && pom.key($0) == key }
            dependencies.append(dependency)
        }
        pom.dependencies = dependencies
        return pom
    }

    /// Coordinates read from metadata name cache paths and URLs, so a
    /// component must not escape its directory.
    static func coordinate(group: String, artifact: String, version: String) throws -> MavenCoordinate {
        let coordinate = MavenCoordinate(module: MavenModuleID(group: group, artifact: artifact), version: version)
        guard [group, artifact, version].allSatisfy(Self.isSafePathComponent) else {
            throw MavenResolutionError.invalidCoordinate(coordinate.description)
        }
        return coordinate
    }

    static func isSafePathComponent(_ text: String) -> Bool {
        !text.isEmpty && text != "." && text != ".." && !text.contains("/") && !text.contains("\\")
            && !text.contains("..") && !text.contains(":")
    }
}
