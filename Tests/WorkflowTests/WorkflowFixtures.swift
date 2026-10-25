// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Benchmark
import Foundation
import Report

func writeCModuleDependencyPackage(at package: URL, explicitModuleMap: Bool) throws {
  try writeFile(
    """
    // swift-tools-version: 6.3
    import PackageDescription

    let package = Package(
      name: "CModuleDependency",
      products: [
        .library(name: "CModuleDependency", targets: ["CModuleDependency"])
      ],
      targets: [
        .target(
          name: "CModuleDependency",
          path: "Sources/CModuleDependency",
          publicHeadersPath: "include"
        )
      ]
    )
    """,
    to: package.appendingPathComponent("Package.swift")
  )
  try writeFile(
    """
    #ifndef CMODULE_DEPENDENCY_H
    #define CMODULE_DEPENDENCY_H

    int c_module_dependency_value(void);

    #endif
    """,
    to: package.appendingPathComponent(
      "Sources/CModuleDependency/include/CModuleDependency.h"
    )
  )
  if explicitModuleMap {
    try writeFile(
      """
      module CModuleDependency {
        header "CModuleDependency.h"
        export *
      }
      """,
      to: package.appendingPathComponent(
        "Sources/CModuleDependency/include/module.modulemap"
      )
    )
  }
  try writeFile(
    """
    #include "CModuleDependency.h"

    int c_module_dependency_value(void) {
      return 42;
    }
    """,
    to: package.appendingPathComponent("Sources/CModuleDependency/CModuleDependency.c")
  )
  // A vendored XCFramework slice the host must never load: clang rejects its
  // module map.
  try writeFile(
    "module Stray {\n  not a module map\n}\n",
    to: package.appendingPathComponent(
      "Vendor/Stray.xcframework/ios-arm64/Headers/module.modulemap"
    )
  )
}

/// A package whose benchmarks call C, Objective-C and C++ targets, a static
/// XCFramework and a resource bundle, plus a test-target benchmark whose
/// `@Test` attribute shares the function's line.
func writeMixedTargetPackage(at package: URL, swiftBenchmarkRoot: URL) throws {
  try writeFile(
    """
    // swift-tools-version: 6.3
    import PackageDescription

    let package = Package(
      name: "MixedTargets",
      platforms: [.macOS(.v15)],
      dependencies: [
        .package(name: "swift-benchmark", path: \(swiftStringLiteral(swiftBenchmarkRoot.path)))
      ],
      targets: [
        .target(name: "CCounter"),
        .target(name: "ObjCCounter"),
        .target(name: "CxxCounter"),
        .binaryTarget(name: "BinaryCounter", path: "BinaryCounter.xcframework"),
        .target(
          name: "MixedLibrary",
          dependencies: [
            "CCounter", "ObjCCounter", "CxxCounter", "BinaryCounter",
            .product(name: "Benchmark", package: "swift-benchmark"),
          ],
          resources: [.process("Resources")]
        ),
        .testTarget(
          name: "MixedTests",
          dependencies: [
            "MixedLibrary",
            .product(name: "BenchmarkTesting", package: "swift-benchmark"),
          ]
        ),
      ]
    )
    """,
    to: package.appendingPathComponent("Package.swift")
  )
  let files = [
    "Sources/CCounter/include/CCounter.h": "int c_counter_value(void);\n",
    "Sources/CCounter/CCounter.c":
      "#include \"CCounter.h\"\nint c_counter_value(void) { return 1; }\n",
    "Sources/ObjCCounter/include/ObjCCounter.h":
      "#import <Foundation/Foundation.h>\n@interface ObjCCounter : NSObject\n+ (NSInteger)value;\n@end\n",
    "Sources/ObjCCounter/ObjCCounter.m":
      "#import \"ObjCCounter.h\"\n@implementation ObjCCounter\n+ (NSInteger)value { return 2; }\n@end\n",
    "Sources/CxxCounter/include/CxxCounter.h":
      "#ifdef __cplusplus\nextern \"C\" {\n#endif\nint cxx_counter_value(void);\n#ifdef __cplusplus\n}\n#endif\n",
    "Sources/CxxCounter/CxxCounter.cpp":
      "#include \"CxxCounter.h\"\n#include <vector>\nint cxx_counter_value(void) { std::vector<int> v{1, 2}; return static_cast<int>(v.size()) + 1; }\n",
    "Sources/MixedLibrary/Resources/value.txt": "4\n",
    "Sources/MixedLibrary/Counters.swift": """
    import BinaryCounter
    import Benchmark
    import CCounter
    import CxxCounter
    import Foundation
    import ObjCCounter

    public enum Counters {
      public static func total() -> Int {
        let url = Bundle.module.url(forResource: "value", withExtension: "txt")!
        let text = try! String(contentsOf: url, encoding: .utf8)
        let resource = Int(text.trimmingCharacters(in: .whitespacesAndNewlines))!
        return Int(c_counter_value()) + ObjCCounter.value() + Int(cxx_counter_value())
          + Int(binary_counter_value()) + resource
      }
    }

    @BenchmarkSuite("Mixed")
    struct MixedBenchmarks {
      @Benchmark("Total")
      func total() {
        precondition(Counters.total() == 15)
      }
    }
    """,
    "Tests/MixedTests/SameLine.swift": """
    import BenchmarkTesting
    import MixedLibrary
    import Testing

    struct SameLineBenchmarks {
      @Test(.benchmark()) func sameLine() { precondition(Counters.total() == 15) }
    }
    """,
    "binary/include/BinaryCounter.h": "int binary_counter_value(void);\n",
    "binary/include/module.modulemap":
      "module BinaryCounter {\n  header \"BinaryCounter.h\"\n  export *\n}\n",
    "binary/BinaryCounter.c":
      "#include \"BinaryCounter.h\"\nint binary_counter_value(void) { return 5; }\n",
  ]
  for (path, contents) in files {
    try writeFile(contents, to: package.appendingPathComponent(path))
  }

  let binary = package.appendingPathComponent("binary")
  let object = binary.appendingPathComponent("BinaryCounter.o").path
  let library = binary.appendingPathComponent("libBinaryCounter.a").path
  _ = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: [
      "clang", "-c", binary.appendingPathComponent("BinaryCounter.c").path, "-o", object,
      "-I", binary.appendingPathComponent("include").path,
      "-arch", "arm64", "-arch", "x86_64", "-mmacosx-version-min=15.0",
    ]
  )
  _ = try runProcess(
    executable: "/usr/bin/xcrun", arguments: ["libtool", "-static", "-o", library, object])
  _ = try runProcess(
    executable: "/usr/bin/xcrun",
    arguments: [
      "xcodebuild", "-create-xcframework", "-library", library,
      "-headers", binary.appendingPathComponent("include").path,
      "-output", package.appendingPathComponent("BinaryCounter.xcframework").path,
    ]
  )
}

func initializeGitRepository(at directory: URL) throws {
  _ = try runProcess(
    executable: "/usr/bin/env",
    arguments: ["git", "-C", directory.path, "init", "-q"]
  )
  _ = try runProcess(
    executable: "/usr/bin/env",
    arguments: ["git", "-C", directory.path, "checkout", "-q", "-B", "master"]
  )
  _ = try runProcess(
    executable: "/usr/bin/env",
    arguments: ["git", "-C", directory.path, "add", "."]
  )
  _ = try runProcess(
    executable: "/usr/bin/env",
    arguments: [
      "git",
      "-C",
      directory.path,
      "-c",
      "user.name=swift-benchmark-tests",
      "-c",
      "user.email=swift-benchmark-tests@example.invalid",
      "commit",
      "-q",
      "-m",
      "Initial test fixture",
    ]
  )
}

func writeCModuleBenchmarkPackage(
  at package: URL,
  dependency: URL,
  swiftBenchmarkRoot: URL
) throws {
  let dependencyURL = dependency.absoluteURL
  try writeFile(
    """
    // swift-tools-version: 6.3
    import PackageDescription

    let package = Package(
      name: "CModuleBenchmarkPackage",
      platforms: [.macOS(.v15)],
      dependencies: [
        .package(name: "swift-benchmark", path: \(swiftStringLiteral(swiftBenchmarkRoot.path))),
        .package(url: \(swiftStringLiteral(dependencyURL.absoluteString)), branch: "master")
      ],
      targets: [
        .target(
          name: "CModuleBenchmarkLibrary",
          dependencies: [
            .product(name: "Benchmark", package: "swift-benchmark"),
            .product(name: "CModuleDependency", package: "CModuleDependency")
          ]
        )
      ]
    )
    """,
    to: package.appendingPathComponent("Package.swift")
  )
  try writeFile(
    """
    import Benchmark
    import CModuleDependency

    @BenchmarkSuite("CModuleFixture", .tag("cModule"))
    struct CModuleFixtureBenchmarks {
      @Benchmark("CModuleNoop")
      func noop() {
        blackHole(c_module_dependency_value())
      }
    }
    """,
    to: package.appendingPathComponent(
      "Sources/CModuleBenchmarkLibrary/LibraryBenchmarks.swift"
    )
  )
}

func writeFakeXcrun(to path: String) throws {
  let script = """
    #!/bin/sh
    output=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --output) shift; output="$1" ;;
        --launch) shift; break ;;
      esac
      shift
    done
    executable="$1"
    shift
    if [ "$1" = "--" ]; then
      shift
    fi
    "$executable" "$@" || exit 54
    if [ -n "$output" ]; then
      mkdir -p "$output"
    fi
    exit 0
    """
  try script.write(toFile: path, atomically: true, encoding: .utf8)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],
    ofItemAtPath: path
  )
}

/// A shell script that answers the host protocol with a plan and a
/// measurement recorded in this process, and logs its arguments.
struct FakeHost {
  let directory: URL
  let host: URL
  private let launchesURL: URL

  init(buildConfiguration: String) async throws {
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("swift-benchmark-fake-host-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    host = directory.appendingPathComponent("host")
    launchesURL = directory.appendingPathComponent("launches")
    let planURL = directory.appendingPathComponent("plan.json")
    let measurementURL = directory.appendingPathComponent("measurement.json")
    var metadata = RunMetadata.local(id: "run:fake-host")
    metadata.buildConfiguration = buildConfiguration
    try await BenchmarkHost.output(
      discoveries: [FakeHostDiscovery.self], arguments: ["list"], metadata: metadata
    ).write(to: planURL)
    try await BenchmarkHost.output(
      discoveries: [FakeHostDiscovery.self], arguments: ["measure"], metadata: metadata
    ).write(to: measurementURL)
    try """
    #!/bin/sh
    echo "$*" >> '\(launchesURL.path)'
    command="$1"
    while [ "$#" -gt 0 ]; do
      if [ "$1" = "--output" ]; then output="$2"; fi
      shift
    done
    if [ "$command" = list ]; then
      cp '\(planURL.path)' "$output"
    else
      cp '\(measurementURL.path)' "$output"
    fi
    """.write(to: host, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
  }

  /// The arguments of each launch, in order.
  func launches() throws -> [String] {
    try String(contentsOf: launchesURL, encoding: .utf8)
      .split(separator: "\n")
      .map(String.init)
  }

  func remove() {
    try? FileManager.default.removeItem(at: directory)
  }
}

private enum FakeHostDiscovery: _BenchmarkDiscovery {
  // swift-format-ignore: AlwaysUseLowerCamelCase
  static var __benchmarkSuites: [BenchmarkSuite] {
    [
      BenchmarkSuite(
        "FakeHost",
        configuration: BenchmarkConfiguration(
          warmup: .none, iterations: .iterations(1), batching: .fixed(1))
      ) {
        Benchmark("First") { blackHole(1) }
        Benchmark("Second") { blackHole(2) }
      }
    ]
  }
}
