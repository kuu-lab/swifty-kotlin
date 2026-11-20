#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite("Driver.MavenDependencyResolver")
struct MavenDependencyResolverTests {
    /// A `file://` Maven repository plus an empty download cache.
    private struct Repository {
        let root: URL
        let cache: URL

        func publish(_ coordinate: String, files: [String: String]) throws {
            let parsed = try #require(MavenCoordinate(parsing: coordinate))
            let directory = root.appendingPathComponent(parsed.directory, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (suffix, contents) in files {
                try Data(contents.utf8).write(to: directory.appendingPathComponent(parsed.fileName(suffix)))
            }
        }

        func resolve(_ roots: [String], offline: Bool = false) throws -> [String] {
            let repositories = MavenRepositorySet(
                repositories: [root.absoluteString], cacheDirectory: cache.path, offline: offline
            )
            return try MavenDependencyResolver(repositories: repositories)
                .resolve(roots.map { try #require(MavenCoordinate(parsing: $0)) })
                .map { "\($0.coordinate)|\($0.file.lastPathComponent)" }
        }
    }

    private func withRepository(_ body: (Repository) throws -> Void) throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("maven-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let repository = Repository(
            root: base.appendingPathComponent("repo", isDirectory: true),
            cache: base.appendingPathComponent("cache", isDirectory: true)
        )
        try FileManager.default.createDirectory(at: repository.root, withIntermediateDirectories: true)
        try body(repository)
    }

    private func module(
        _ coordinate: String, file: String? = nil,
        dependencies: [(String, String)] = [], constraints: [(String, String)] = [],
        availableAt: String? = nil, platform: String = "androidJvm"
    ) throws -> String {
        let parsed = try #require(MavenCoordinate(parsing: coordinate))
        func entries(_ list: [(String, String)]) -> String {
            list.map { module, version in
                let parts = module.split(separator: ":")
                return #"{"group":"\#(parts[0])","module":"\#(parts[1])","version":{"requires":"\#(version)"}}"#
            }.joined(separator: ",")
        }
        var runtime = #"{"name":"runtime","attributes":{"org.gradle.category":"library","org.gradle.usage":"java-runtime","org.jetbrains.kotlin.platform.type":"\#(platform)"}"#
        if let availableAt, let target = MavenCoordinate(parsing: availableAt) {
            runtime += #","available-at":{"url":"../x","group":"\#(target.module.group)","module":"\#(target.module.artifact)","version":"\#(target.version)"}"#
        } else {
            runtime += #","dependencies":[\#(entries(dependencies))],"dependencyConstraints":[\#(entries(constraints))]"#
            if let file {
                runtime += #","files":[{"name":"\#(parsed.fileName(file))","url":"\#(parsed.fileName(file))"}]"#
            }
        }
        runtime += "}"
        // A Kotlin/Native variant must never be picked for an Android build.
        let native = #"{"name":"native","attributes":{"org.gradle.category":"library","org.gradle.usage":"java-runtime","org.jetbrains.kotlin.platform.type":"native"},"files":[{"name":"wrong.klib","url":"wrong.klib"}]}"#
        return #"{"formatVersion":"1.1","variants":[\#(native),\#(runtime)]}"#
    }

    @Test
    func versionOrderingFollowsGradle() {
        #expect(MavenVersion.isNewer("1.10.0", than: "1.9.3"))
        #expect(MavenVersion.isNewer("1.7.8", than: "1.7.8-rc01"))
        #expect(MavenVersion.isNewer("1.8.0-beta01", than: "1.8.0-alpha05"))
        #expect(MavenVersion.isNewer("1.8.0-rc01", than: "1.8.0-beta01"))
        #expect(MavenVersion.isNewer("2.0", than: "1.99.99"))
        #expect(MavenVersion.isNewer("1.0.1", than: "1.0"))
        #expect(MavenVersion.compare("1.0", "1.0") == .orderedSame)
        #expect(MavenCoordinate(parsing: "a:b") == nil)
        #expect(MavenCoordinate(parsing: "androidx.core:core:1.13.1")?.directory == "androidx/core/core/1.13.1")
    }

    @Test
    func resolvesMultiplatformRedirectsAndNewestVersion() throws {
        try withRepository { repo in
            // `ui` is a Kotlin Multiplatform root; its Android variant lives in `ui-android`.
            try repo.publish("g:ui:1.0", files: [".module": try module("g:ui:1.0", availableAt: "g:ui-android:1.0")])
            try repo.publish("g:ui-android:1.0", files: [
                ".module": try module("g:ui-android:1.0", file: ".aar",
                                      dependencies: [("g:core", "1.0"), ("org.jetbrains.kotlin:kotlin-stdlib", "1.9.0")]),
                ".aar": "aar",
            ])
            // `extra` asks for a newer `core`; the newest requested version wins.
            try repo.publish("g:extra:1.0", files: [
                ".module": try module("g:extra:1.0", file: ".jar", dependencies: [("g:core", "1.2")]),
                ".jar": "jar",
            ])
            try repo.publish("g:core:1.0", files: [
                ".module": try module("g:core:1.0", file: ".jar", dependencies: [("g:old-only", "1.0")]),
                ".jar": "old",
            ])
            try repo.publish("g:core:1.2", files: [".module": try module("g:core:1.2", file: ".jar"), ".jar": "new"])

            let resolved = try repo.resolve(["g:ui:1.0", "g:extra:1.0"])
            // Breadth-first order (the redirect target follows both roots). The
            // losing core 1.0 contributes nothing (not even its dependency), the
            // `ui` root has no files, and kotlin-stdlib is supplied by the
            // kswiftc runtime instead.
            #expect(resolved == [
                "g:extra:1.0|extra-1.0.jar",
                "g:ui-android:1.0|ui-android-1.0.aar",
                "g:core:1.2|core-1.2.jar",
            ])
        }
    }

    @Test
    func dependencyConstraintsAlignModulesAlreadyInTheGraph() throws {
        try withRepository { repo in
            try repo.publish("g:app:1.0", files: [
                ".module": try module("g:app:1.0", file: ".jar", dependencies: [("g:runtime", "1.0")],
                                      constraints: [("g:runtime", "1.5"), ("g:unrelated", "9.0")]),
                ".jar": "app",
            ])
            try repo.publish("g:runtime:1.5", files: [".module": try module("g:runtime:1.5", file: ".jar"), ".jar": "rt"])

            #expect(try repo.resolve(["g:app:1.0"]) == ["g:app:1.0|app-1.0.jar", "g:runtime:1.5|runtime-1.5.jar"])
        }
    }

    @Test
    func pomFallbackInheritsParentPropertiesAndManagedVersions() throws {
        try withRepository { repo in
            try repo.publish("g:parent:3", files: [".pom": """
                <project><groupId>g</groupId><artifactId>parent</artifactId><version>3</version>
                  <packaging>pom</packaging>
                  <properties><lib.version>2.1</lib.version></properties>
                  <dependencyManagement><dependencies>
                    <dependency><groupId>g</groupId><artifactId>managed</artifactId><version>${lib.version}</version></dependency>
                  </dependencies></dependencyManagement>
                </project>
                """])
            try repo.publish("g:legacy:1.0", files: [
                ".pom": """
                    <project>
                      <parent><groupId>g</groupId><artifactId>parent</artifactId><version>3</version></parent>
                      <artifactId>legacy</artifactId><version>1.0</version><packaging>aar</packaging>
                      <dependencies>
                        <dependency><groupId>${project.groupId}</groupId><artifactId>managed</artifactId></dependency>
                        <dependency><groupId>g</groupId><artifactId>tests</artifactId><version>1</version><scope>test</scope></dependency>
                        <dependency><groupId>g</groupId><artifactId>opt</artifactId><version>1</version><optional>true</optional></dependency>
                      </dependencies>
                    </project>
                    """,
                ".aar": "aar",
            ])
            try repo.publish("g:managed:2.1", files: [
                ".pom": "<project><groupId>g</groupId><artifactId>managed</artifactId><version>2.1</version></project>",
                ".jar": "jar",
            ])

            #expect(try repo.resolve(["g:legacy:1.0"]) == [
                "g:legacy:1.0|legacy-1.0.aar", "g:managed:2.1|managed-2.1.jar",
            ])
            // Everything is now cached, including the `.module` misses.
            try FileManager.default.removeItem(at: repo.root)
            #expect(try repo.resolve(["g:legacy:1.0"], offline: true).count == 2)
        }
    }

    @Test
    func pomInheritsParentDependenciesAndImportsBOMs() throws {
        try withRepository { repo in
            try repo.publish("g:bom:1", files: [".pom": """
                <project><groupId>g</groupId><artifactId>bom</artifactId><version>1</version><packaging>pom</packaging>
                  <dependencyManagement><dependencies>
                    <dependency><groupId>g</groupId><artifactId>helper</artifactId><version>2</version></dependency>
                    <dependency><groupId>g</groupId><artifactId>pinned</artifactId><version>9</version></dependency>
                  </dependencies></dependencyManagement>
                </project>
                """])
            try repo.publish("g:parent:1", files: [".pom": """
                <project><groupId>g</groupId><artifactId>parent</artifactId><version>1</version><packaging>pom</packaging>
                  <dependencies>
                    <dependency><groupId>g</groupId><artifactId>inherited</artifactId><version>1</version></dependency>
                    <dependency><groupId>g</groupId><artifactId>overridden</artifactId><version>1</version></dependency>
                  </dependencies>
                </project>
                """])
            try repo.publish("g:widget:1", files: [
                ".pom": """
                    <project>
                      <parent><groupId>g</groupId><artifactId>parent</artifactId><version>1</version></parent>
                      <artifactId>widget</artifactId>
                      <dependencyManagement><dependencies>
                        <dependency><groupId>g</groupId><artifactId>pinned</artifactId><version>3</version></dependency>
                        <dependency><groupId>g</groupId><artifactId>bom</artifactId><version>1</version><type>pom</type><scope>import</scope></dependency>
                      </dependencies></dependencyManagement>
                      <dependencies>
                        <dependency><groupId>g</groupId><artifactId>helper</artifactId></dependency>
                        <dependency><groupId>g</groupId><artifactId>pinned</artifactId></dependency>
                        <dependency><groupId>g</groupId><artifactId>overridden</artifactId><version>2</version></dependency>
                      </dependencies>
                    </project>
                    """,
                ".jar": "widget",
            ])
            for coordinate in ["g:inherited:1", "g:overridden:2", "g:helper:2", "g:pinned:3"] {
                let artifact = try #require(MavenCoordinate(parsing: coordinate)).module.artifact
                try repo.publish(coordinate, files: [
                    ".pom": "<project><groupId>g</groupId><artifactId>\(artifact)</artifactId><version>0</version></project>",
                    ".jar": artifact,
                ])
            }
            // Parent dependencies are inherited unless the child redeclares them,
            // imported BOM versions apply, and the POM's own management wins over the BOM.
            #expect(Set(try repo.resolve(["g:widget:1"])) == [
                "g:widget:1|widget-1.jar", "g:inherited:1|inherited-1.jar", "g:overridden:2|overridden-2.jar",
                "g:helper:2|helper-2.jar", "g:pinned:3|pinned-3.jar",
            ])
        }
    }

    @Test
    func unfetchableMetadataOfALosingVersionIsNotFatal() throws {
        try withRepository { repo in
            try repo.publish("g:app:1", files: [
                ".module": try module("g:app:1", file: ".jar", dependencies: [("g:core", "1"), ("g:bridge", "1")]),
                ".jar": "app",
            ])
            try repo.publish("g:core:1", files: [
                ".module": try module("g:core:1", file: ".jar", dependencies: [("g:obsolete", "1")]), ".jar": "old",
            ])
            try repo.publish("g:bridge:1", files: [
                ".module": try module("g:bridge:1", file: ".jar", dependencies: [("g:core", "2")]), ".jar": "bridge",
            ])
            try repo.publish("g:core:2", files: [".module": try module("g:core:2", file: ".jar"), ".jar": "new"])
            // g:obsolete:1 is published nowhere, but only core 1 (which loses) needs it.
            #expect(try repo.resolve(["g:app:1"]) == [
                "g:app:1|app-1.jar", "g:core:2|core-2.jar", "g:bridge:1|bridge-1.jar",
            ])
        }
    }

    @Test
    func metadataCannotNameFilesOutsideTheCache() throws {
        try withRepository { repo in
            func isInvalidCoordinate(_ body: () throws -> Void) -> Bool {
                do { try body() } catch MavenResolutionError.invalidCoordinate { return true } catch {}
                return false
            }
            // A dependency coordinate climbing out of its directory.
            try repo.publish("g:evil:1", files: [".module": try module("g:evil:1", file: ".jar", dependencies: [("../../g:escape", "1")])])
            #expect(isInvalidCoordinate { _ = try repo.resolve(["g:evil:1"]) })
            let resolver = MavenDependencyResolver(repositories: MavenRepositorySet(
                repositories: [repo.root.absoluteString], cacheDirectory: repo.cache.path, offline: false
            ))
            let escaping = MavenCoordinate(module: MavenModuleID(group: "g", artifact: "x"), version: "../../1")
            #expect(isInvalidCoordinate { _ = try resolver.resolve([escaping]) })
            // A file URL climbing out of the version directory is not an artifact.
            try repo.publish("g:files:1", files: [".module": """
                {"formatVersion":"1.1","variants":[{"name":"runtime","attributes":{"org.gradle.category":"library",\
                "org.gradle.usage":"java-runtime"},"files":[{"name":"x","url":"files-1/../../../../escape.jar"}]}]}
                """])
            #expect(try repo.resolve(["g:files:1"]).isEmpty)
        }
    }

    @Test
    func missingArtifactsAndOfflineMissesAreReported() throws {
        try withRepository { repo in
            #expect(throws: MavenResolutionError.self) { try repo.resolve(["g:absent:1.0"]) }
            #expect(throws: MavenResolutionError.self) { try repo.resolve(["g:other:1.0"], offline: true) }
        }
    }
}
#endif
