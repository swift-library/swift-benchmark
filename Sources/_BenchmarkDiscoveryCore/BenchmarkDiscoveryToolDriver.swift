import Foundation

public enum BenchmarkDiscoveryToolDriver {
  public static func run(arguments: [String]) {
    do {
      try BenchmarkDiscoveryCommand.run(arguments)
    } catch {
      fputs("BenchmarkDiscoveryTool: \(error)\n", stderr)
      Foundation.exit(1)
    }
  }
}

enum BenchmarkDiscoveryCommand {
  static func run(_ arguments: [String]) throws {
    guard arguments.first == "discover" else {
      throw ToolError.invalidArguments(
        "usage: BenchmarkDiscoveryTool discover --targets-manifest <path> --work-directory <path> --output-plan <path>"
      )
    }

    let options = try DiscoverOptions(arguments: Array(arguments.dropFirst()))
    let manifestURL = URL(fileURLWithPath: options.targetsManifestPath)
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(TargetManifest.self, from: manifestData)
    let plan = try BenchmarkDiscoveryPlanner(
      manifest: manifest,
      workDirectory: URL(fileURLWithPath: options.workDirectoryPath)
    ).makePlan()

    let outputURL = URL(fileURLWithPath: options.outputPlanPath)
    try FileManager.default.createDirectory(
      at: outputURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(plan).write(to: outputURL)
  }
}

struct DiscoverOptions {
  var targetsManifestPath: String
  var workDirectoryPath: String
  var outputPlanPath: String

  init(arguments: [String]) throws {
    var targetsManifestPath: String?
    var workDirectoryPath: String?
    var outputPlanPath: String?
    var index = arguments.startIndex

    while index < arguments.endIndex {
      let argument = arguments[index]
      switch argument {
      case "--targets-manifest":
        targetsManifestPath = try Self.value(after: argument, in: arguments, index: &index)
      case "--work-directory":
        workDirectoryPath = try Self.value(after: argument, in: arguments, index: &index)
      case "--output-plan":
        outputPlanPath = try Self.value(after: argument, in: arguments, index: &index)
      default:
        throw ToolError.invalidArguments("unknown argument \(argument)")
      }
      index = arguments.index(after: index)
    }

    guard let targetsManifestPath, let workDirectoryPath, let outputPlanPath else {
      throw ToolError.invalidArguments(
        "usage: BenchmarkDiscoveryTool discover --targets-manifest <path> --work-directory <path> --output-plan <path>"
      )
    }

    self.targetsManifestPath = targetsManifestPath
    self.workDirectoryPath = workDirectoryPath
    self.outputPlanPath = outputPlanPath
  }

  private static func value(
    after option: String,
    in arguments: [String],
    index: inout Array<String>.Index
  ) throws -> String {
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
      throw ToolError.invalidArguments("missing value for \(option)")
    }
    index = valueIndex
    return arguments[valueIndex]
  }
}

struct TargetManifest: Codable {
  var targets: [TargetDescription]
}

struct TargetDescription: Codable {
  var name: String
  var moduleName: String
  var kind: String
  var sourcePaths: [String]

  var isExecutable: Bool { kind == "executable" }
  var isMacro: Bool { kind == "macro" }
  var isSnippet: Bool { kind == "snippet" }
  var isTest: Bool { kind == "test" }
}

struct BenchmarkDiscoveryPlan: Codable {
  var nativeDiscoveries: [NativeDiscoveryReference]
  var testingBridges: [TestingBridgeReference]
  var generatedHostSourcePath: String
  var discoveredTargetNames: [String]
  var requiresSwiftTesting: Bool
  var discoveryExpressions: [String]

  var isEmpty: Bool {
    nativeDiscoveries.isEmpty && testingBridges.isEmpty
  }
}

struct NativeDiscoveryReference: Codable {
  var moduleName: String
  var targetName: String
  var typeName: String
  var discoveryTypeName: String
}

struct TestingBridgeReference: Codable {
  var moduleName: String
  var targetName: String
  var discoveryTypeName: String
  var sourcePath: String
}

struct BenchmarkDiscoveryPlanner {
  var manifest: TargetManifest
  var workDirectory: URL

  func makePlan() throws -> BenchmarkDiscoveryPlan {
    var nativeDiscoveries: [NativeDiscoveryReference] = []
    var testingBridges: [TestingBridgeReference] = []
    var skippedExecutableTargets: [String] = []
    var skippedTestTargets: [String] = []
    var diagnostics: [String] = []

    for target in manifest.targets where !target.isMacro && !target.isSnippet {
      if target.isTest {
        if let bridge = try testingBridge(for: target, diagnostics: &diagnostics) {
          testingBridges.append(bridge)
          continue
        }
        if try !NativeBenchmarkScanner(target: target).scan().isEmpty {
          skippedTestTargets.append(target.name)
        }
        continue
      }

      let declarations = try NativeBenchmarkScanner(target: target).scan()
      guard !declarations.isEmpty else {
        continue
      }

      guard !target.isExecutable else {
        skippedExecutableTargets.append(target.name)
        continue
      }

      nativeDiscoveries.append(
        contentsOf: declarations.map { declaration in
          NativeDiscoveryReference(
            moduleName: target.moduleName,
            targetName: target.name,
            typeName: declaration,
            discoveryTypeName: "__BenchmarkDiscovery_\(sanitizedIdentifier(declaration))"
          )
        }
      )
    }

    if !diagnostics.isEmpty {
      throw ToolError.diagnostics(diagnostics)
    }
    if nativeDiscoveries.isEmpty, testingBridges.isEmpty, !skippedExecutableTargets.isEmpty {
      throw ToolError.diagnostics([
        "Benchmark declarations were found only in executable target(s) \(skippedExecutableTargets.sorted().joined(separator: ", ")). Move production benchmark declarations to a library target for no-boilerplate package discovery, or use --host as an advanced override."
      ])
    }
    if nativeDiscoveries.isEmpty, testingBridges.isEmpty, !skippedTestTargets.isEmpty {
      throw ToolError.diagnostics([
        "Benchmark declarations were found only in test target(s) \(skippedTestTargets.sorted().joined(separator: ", ")). Move production benchmark declarations to a library target for no-boilerplate package discovery, or use --host as an advanced override."
      ])
    }

    let discoveryExpressions = nativeDiscoveries.map {
      "\($0.moduleName).\($0.discoveryTypeName).self"
    } + testingBridges.map {
      "\($0.discoveryTypeName).self"
    }
    let hostSourcePath = try writeGeneratedHost(
      nativeDiscoveries: nativeDiscoveries,
      discoveryExpressions: discoveryExpressions
    )
    return BenchmarkDiscoveryPlan(
      nativeDiscoveries: nativeDiscoveries,
      testingBridges: testingBridges,
      generatedHostSourcePath: hostSourcePath.path,
      discoveredTargetNames: Array(
        Set(nativeDiscoveries.map(\.targetName) + testingBridges.map(\.targetName))
      ).sorted(),
      requiresSwiftTesting: !testingBridges.isEmpty,
      discoveryExpressions: discoveryExpressions
    )
  }

  private func testingBridge(
    for target: TargetDescription,
    diagnostics: inout [String]
  ) throws -> TestingBridgeReference? {
    let result = try TestingBridgeScanner(target: target).scan()
    diagnostics.append(contentsOf: result.diagnostics)

    guard !result.suites.isEmpty else {
      return nil
    }

    let directory = workDirectory.appendingPathComponent("BenchmarkTestingBridge")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let discoveryName = "__BenchmarkTestingDiscovery_\(sanitizedIdentifier(target.name))"
    let outputURL = directory.appendingPathComponent("\(sanitizedIdentifier(target.name)).swift")
    let source = BridgeSourceGenerator(
      moduleName: target.moduleName,
      discoveryName: discoveryName,
      suites: result.suites
    ).render()
    try source.write(to: outputURL, atomically: true, encoding: .utf8)

    return TestingBridgeReference(
      moduleName: target.moduleName,
      targetName: target.name,
      discoveryTypeName: discoveryName,
      sourcePath: outputURL.path
    )
  }

  private func writeGeneratedHost(
    nativeDiscoveries: [NativeDiscoveryReference],
    discoveryExpressions: [String]
  ) throws -> URL {
    let directory = workDirectory.appendingPathComponent("GeneratedBenchmarkHost")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let sourceURL = directory.appendingPathComponent("main.swift")
    let imports = Set(nativeDiscoveries.map(\.moduleName)).sorted()
      .map { "import \($0)" }
      .joined(separator: "\n")
    let discoveryList = discoveryExpressions
      .map { "    \($0)" }
      .joined(separator: ",\n")
    let source = """
      import Benchmark
      import Report
      \(imports)

      @main
      struct GeneratedBenchmarkHost {
        static func main() async throws {
          try await BenchmarkHost.run(discoveries: [
      \(discoveryList)
          ])
        }
      }
      """
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    return sourceURL
  }
}

struct NativeBenchmarkScanner {
  var target: TargetDescription

  func scan() throws -> [String] {
    var declarations: [String] = []
    var seen = Set<String>()
    let typePattern = try NSRegularExpression(
      pattern: #"(?m)\b(?:struct|enum|actor|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#,
      options: []
    )

    for path in target.sourcePaths {
      let source = stripStringLiteralsAndComments(
        try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
      )
      let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
      for index in lines.indices where lines[index].contains("@BenchmarkSuite") {
        let end = lines.index(index, offsetBy: 8, limitedBy: lines.endIndex) ?? lines.endIndex
        let window = lines[index..<end].joined(separator: "\n")
        let range = NSRange(window.startIndex..<window.endIndex, in: window)
        guard let match = typePattern.firstMatch(in: window, range: range),
          let typeRange = Range(match.range(at: 1), in: window)
        else {
          continue
        }
        let declaration = String(window[typeRange])
        if seen.insert(declaration).inserted {
          declarations.append(declaration)
        }
      }
    }
    return declarations
  }
}

private struct TestingBridgeScanner {
  var target: TargetDescription

  func scan() throws -> ScanResult {
    var suites: [DiscoveredSuite] = []
    var diagnostics: [String] = []

    for path in target.sourcePaths {
      let url = URL(fileURLWithPath: path)
      let source = try String(contentsOf: url, encoding: .utf8)
      var scanner = SourceScanner(
        targetName: target.name,
        filePath: path,
        source: source
      )
      scanner.scan()
      suites.append(contentsOf: scanner.suites)
      diagnostics.append(contentsOf: scanner.diagnostics)
    }

    return ScanResult(suites: suites, diagnostics: diagnostics)
  }
}

private struct SourceScanner {
  var targetName: String
  var filePath: String
  var source: String
  var suites: [DiscoveredSuite] = []
  var diagnostics: [String] = []

  private var contexts: [SuiteContext] = []
  private var braceDepth = 0
  private var pendingAttributes: [PendingAttribute] = []

  init(targetName: String, filePath: String, source: String) {
    self.targetName = targetName
    self.filePath = filePath
    self.source = source
  }

  mutating func scan() {
    let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    var index = 0
    while index < lines.count {
      let line = stripLineComment(lines[index])
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      if trimmed.hasPrefix("@") {
        let attribute = collectAttribute(startingAt: index, in: lines)
        pendingAttributes.append(attribute.value)
        index = attribute.nextIndex
        continue
      }

      if let type = parseTypeDeclaration(line) {
        scanType(type)
      } else if let function = parseFunctionDeclaration(line, lineNumber: index + 1) {
        scanFunction(function, suiteType: contexts.last?.type)
      } else if !trimmed.isEmpty {
        pendingAttributes.removeAll()
      }

      braceDepth += braceDelta(in: line)
      popClosedContexts()
      index += 1
    }
  }

  private mutating func scanType(_ type: TypeDeclaration) {
    let suiteAttribute = pendingAttribute(named: "Suite")
    let suiteInfo = suiteAttribute.map(attributeInfo(from:)) ?? .empty
    pendingAttributes.removeAll()

    let inherited = contexts.last?.isEnrolled == true
    let isEnrolled = inherited || suiteInfo.hasBenchmark
    let suiteName = suiteInfo.displayName ?? type.qualifiedName
    let suiteTraits = (contexts.last?.traits ?? []) + suiteInfo.traits
    contexts.append(
      SuiteContext(
        type: type,
        closeDepth: braceDepth + max(1, braceDelta(in: type.line)),
        isEnrolled: isEnrolled,
        suiteName: suiteName,
        traits: suiteTraits,
        cases: []
      )
    )
  }

  @discardableResult
  private mutating func scanFunction(
    _ function: FunctionDeclaration,
    suiteType: TypeDeclaration?
  ) -> DiscoveredCase? {
    guard let testAttribute = pendingAttribute(named: "Test") else {
      pendingAttributes.removeAll()
      return nil
    }
    pendingAttributes.removeAll()

    let testInfo = attributeInfo(from: testAttribute)
    let context = contexts.last
    let isEnrolled = context?.isEnrolled == true || testInfo.hasBenchmark
    guard isEnrolled else {
      return nil
    }

    let diagnosticPrefix = "\(filePath):\(function.line):\(function.column):"
    if function.isPrivate {
      diagnostics.append(
        "\(diagnosticPrefix) private/fileprivate @Test(.benchmark) cannot be bridged from generated source; make it internal or use @BenchmarkSuite/@Benchmark for same-scope discovery."
      )
      return nil
    }
    if testInfo.hasArguments || !function.parametersAreEmpty {
      diagnostics.append(
        "\(diagnosticPrefix) @Test(arguments:) is not mapped to Benchmark.Dimension; use Benchmark.Dimension for input-size benchmarks."
      )
      return nil
    }
    if suiteType?.kind == .enum, !function.isStatic {
      diagnostics.append(
        "\(diagnosticPrefix) instance @Test(.benchmark) methods in enum suites cannot be constructed by the BenchmarkTesting bridge."
      )
      return nil
    }
    if suiteType?.kind == .actor, !function.isStatic {
      diagnostics.append(
        "\(diagnosticPrefix) instance @Test(.benchmark) methods in actor suites cannot be constructed by the BenchmarkTesting bridge."
      )
      return nil
    }

    let discovered = DiscoveredCase(
      name: testInfo.displayName ?? function.name,
      traits: testInfo.traits,
      sourceLocation: BenchmarkSourceLocationLiteral(
        fileID: "\(targetName)/\(URL(fileURLWithPath: filePath).lastPathComponent)",
        filePath: filePath,
        line: function.line,
        column: function.column
      ),
      invocation: invocationExpression(for: function, suiteType: suiteType)
    )

    if contexts.indices.contains(contexts.count - 1) {
      contexts[contexts.count - 1].cases.append(discovered)
    } else {
      suites.append(
        DiscoveredSuite(
          name: targetName,
          traits: [],
          cases: [discovered]
        )
      )
    }
    return discovered
  }

  private func invocationExpression(
    for function: FunctionDeclaration,
    suiteType: TypeDeclaration?
  ) -> String {
    let effectPrefix = "\(function.isThrowing ? "try " : "")\(function.isAsync ? "await " : "")"
    guard let suiteType else {
      return "\(effectPrefix)\(function.name)()"
    }
    if function.isStatic {
      return "\(effectPrefix)\(suiteType.qualifiedName).\(function.name)()"
    }
    return """
      var suite = \(suiteType.qualifiedName)()
      \(effectPrefix)suite.\(function.name)()
      """
  }

  private mutating func popClosedContexts() {
    while let context = contexts.last, braceDepth < context.closeDepth {
      if !context.cases.isEmpty {
        suites.append(
          DiscoveredSuite(
            name: context.suiteName,
            traits: context.traits,
            cases: context.cases
          )
        )
      }
      contexts.removeLast()
    }
  }

  private func pendingAttribute(named name: String) -> PendingAttribute? {
    pendingAttributes.reversed().first { $0.name == name }
  }

  private func collectAttribute(
    startingAt index: Int,
    in lines: [String]
  ) -> (value: PendingAttribute, nextIndex: Int) {
    var text = ""
    var balance = 0
    var lineIndex = index
    let startLine = index + 1
    let startColumn = max(1, (lines[index].firstIndex(of: "@").map { lines[index].distance(from: lines[index].startIndex, to: $0) } ?? 0) + 1)
    var name = ""
    var sawName = false

    while lineIndex < lines.count {
      let line = stripLineComment(lines[lineIndex])
      if lineIndex == index {
        name = attributeName(in: line) ?? ""
        sawName = !name.isEmpty
      }
      text += line + "\n"
      balance += parenDelta(in: line)
      lineIndex += 1
      if sawName, balance <= 0 {
        break
      }
    }

    return (
      PendingAttribute(
        name: name,
        text: text,
        line: startLine,
        column: startColumn
      ),
      lineIndex
    )
  }

  private func parseTypeDeclaration(_ line: String) -> TypeDeclaration? {
    let stripped = stripLineComment(line)
    let pattern = #"(?:(?:public|internal|private|fileprivate|open|final)\s+)*(struct|class|actor|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#
    guard let match = firstMatch(pattern, in: stripped),
      let kindText = capture(1, in: stripped, match: match),
      let name = capture(2, in: stripped, match: match)
    else {
      return nil
    }
    let qualified = (contexts.last?.type.qualifiedName).map { "\($0).\(name)" } ?? name
    return TypeDeclaration(
      qualifiedName: qualified,
      kind: TypeDeclaration.Kind(rawValue: kindText) ?? .struct,
      line: stripped
    )
  }

  private func parseFunctionDeclaration(
    _ line: String,
    lineNumber: Int
  ) -> FunctionDeclaration? {
    let stripped = stripLineComment(line)
    let pattern = #"(?:(?:public|internal|private|fileprivate|open|static|class|mutating|nonmutating)\s+)*func\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)([^\\{]*)"#
    guard let match = firstMatch(pattern, in: stripped),
      let name = capture(1, in: stripped, match: match),
      let parameters = capture(2, in: stripped, match: match),
      let effects = capture(3, in: stripped, match: match)
    else {
      return nil
    }
    let functionStart = stripped.range(of: "func")?.lowerBound ?? stripped.startIndex
    let prefix = String(stripped[..<functionStart])
    let column = (stripped.range(of: "func").map { stripped.distance(from: stripped.startIndex, to: $0.lowerBound) } ?? 0) + 1
    return FunctionDeclaration(
      name: name,
      line: lineNumber,
      column: column,
      isPrivate: prefix.contains("private ") || prefix.contains("fileprivate "),
      isStatic: prefix.contains("static ") || prefix.contains("class "),
      isAsync: effects.contains(" async"),
      isThrowing: effects.contains(" throws") || effects.contains(" rethrows"),
      parametersAreEmpty: parameters.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    )
  }

  private func attributeInfo(from attribute: PendingAttribute) -> AttributeInfo {
    let text = attribute.text
    return AttributeInfo(
      displayName: firstStringLiteral(in: text),
      hasBenchmark: containsBenchmarkTrait(text),
      hasArguments: text.contains("arguments:"),
      traits: benchmarkTraits(from: text) + tagTraits(from: text)
    )
  }

  private func benchmarkTraits(from text: String) -> [String] {
    guard containsBenchmarkTrait(text),
      let configuration = argumentValue(named: "configuration", inCallNamed: "benchmark", text: text)
    else {
      return []
    }
    return [".configuration(\(configuration))"]
  }

  private func tagTraits(from text: String) -> [String] {
    callArguments(named: "tags", in: text).compactMap { argument in
      tagName(from: argument).map { ".tag(\(String(reflecting: $0)))" }
    }
  }

  private func containsBenchmarkTrait(_ text: String) -> Bool {
    text.contains(".benchmark") || text.contains("benchmark(")
  }

  private func tagName(from expression: String) -> String? {
    let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
    if let literal = firstStringLiteral(in: trimmed) {
      return literal
    }
    if trimmed.hasPrefix(".") {
      return String(trimmed.dropFirst())
    }
    return trimmed.split(separator: ".").last.map(String.init)
  }
}

private struct BridgeSourceGenerator {
  var moduleName: String
  var discoveryName: String
  var suites: [DiscoveredSuite]

  func render() -> String {
    """
    import Benchmark
    import BenchmarkTesting
    import Report
    import Testing
    @testable import \(moduleName)

    enum \(discoveryName): _BenchmarkDiscovery {
      static var __benchmarkSuites: [BenchmarkSuite] {
        [
    \(suites.map(renderSuite).joined(separator: ",\n"))
        ]
      }
    }
    """
  }

  private func renderSuite(_ suite: DiscoveredSuite) -> String {
    """
          BenchmarkSuite(\(String(reflecting: suite.name)), traits: \(renderSuiteTraits(suite.traits))) {
    \(suite.cases.map(renderCase).joined(separator: "\n"))
          }
    """
  }

  private func renderCase(_ benchmarkCase: DiscoveredCase) -> String {
    """
            Benchmark(
              \(String(reflecting: benchmarkCase.name)),
              traits: \(renderCaseTraits(benchmarkCase.traits)),
              sourceLocation: \(benchmarkCase.sourceLocation.rendered)
            ) {
    \(indent(benchmarkCase.invocation, spaces: 10))
            }
    """
  }

  private func renderSuiteTraits(_ traits: [String]) -> String {
    traits.isEmpty ? "[]" : "[\(traits.joined(separator: ", "))]"
  }

  private func renderCaseTraits(_ traits: [String]) -> String {
    traits.isEmpty ? "[]" : "[\(traits.joined(separator: ", "))]"
  }

  private func indent(_ text: String, spaces: Int) -> String {
    let prefix = String(repeating: " ", count: spaces)
    return text.split(separator: "\n", omittingEmptySubsequences: false)
      .map { "\(prefix)\($0)" }
      .joined(separator: "\n")
  }
}

private struct ScanResult {
  var suites: [DiscoveredSuite]
  var diagnostics: [String]
}

private struct SuiteContext {
  var type: TypeDeclaration
  var closeDepth: Int
  var isEnrolled: Bool
  var suiteName: String
  var traits: [String]
  var cases: [DiscoveredCase]
}

private struct PendingAttribute {
  var name: String
  var text: String
  var line: Int
  var column: Int
}

private struct TypeDeclaration {
  enum Kind: String {
    case `struct`
    case `class`
    case `actor`
    case `enum`
  }

  var qualifiedName: String
  var kind: Kind
  var line: String
}

private struct FunctionDeclaration {
  var name: String
  var line: Int
  var column: Int
  var isPrivate: Bool
  var isStatic: Bool
  var isAsync: Bool
  var isThrowing: Bool
  var parametersAreEmpty: Bool
}

private struct DiscoveredSuite {
  var name: String
  var traits: [String]
  var cases: [DiscoveredCase]
}

private struct DiscoveredCase {
  var name: String
  var traits: [String]
  var sourceLocation: BenchmarkSourceLocationLiteral
  var invocation: String
}

private struct BenchmarkSourceLocationLiteral {
  var fileID: String
  var filePath: String
  var line: Int
  var column: Int

  var rendered: String {
    "BenchmarkSourceLocation(fileID: \(String(reflecting: fileID)), filePath: \(String(reflecting: filePath)), line: \(line), column: \(column))"
  }
}

private struct AttributeInfo {
  var displayName: String?
  var hasBenchmark: Bool
  var hasArguments: Bool
  var traits: [String]

  static var empty: AttributeInfo {
    AttributeInfo(
      displayName: nil,
      hasBenchmark: false,
      hasArguments: false,
      traits: []
    )
  }
}

private enum ToolError: Error, CustomStringConvertible {
  case invalidArguments(String)
  case diagnostics([String])

  var description: String {
    switch self {
    case .invalidArguments(let message):
      message
    case .diagnostics(let messages):
      messages.joined(separator: "\n")
    }
  }
}

private func firstMatch(_ pattern: String, in text: String) -> NSTextCheckingResult? {
  let regex = try? NSRegularExpression(pattern: pattern, options: [])
  let range = NSRange(text.startIndex..<text.endIndex, in: text)
  return regex?.firstMatch(in: text, options: [], range: range)
}

private func capture(
  _ index: Int,
  in text: String,
  match: NSTextCheckingResult
) -> String? {
  guard let range = Range(match.range(at: index), in: text) else {
    return nil
  }
  return String(text[range])
}

private func attributeName(in line: String) -> String? {
  guard let at = line.firstIndex(of: "@") else {
    return nil
  }
  let suffix = line[line.index(after: at)...]
  let name = suffix.prefix { character in
    character.isLetter || character.isNumber || character == "_"
  }
  return name.isEmpty ? nil : String(name)
}

private func stripLineComment(_ line: String) -> String {
  var inString = false
  var escaped = false
  var index = line.startIndex
  while index < line.endIndex {
    let character = line[index]
    if inString {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        inString = false
      }
    } else if character == "\"" {
      inString = true
    } else if character == "/" {
      let next = line.index(after: index)
      if next < line.endIndex, line[next] == "/" {
        return String(line[..<index])
      }
    }
    index = line.index(after: index)
  }
  return line
}

private func braceDelta(in line: String) -> Int {
  delimiterDelta(in: line, open: "{", close: "}")
}

private func parenDelta(in line: String) -> Int {
  delimiterDelta(in: line, open: "(", close: ")")
}

private func delimiterDelta(in line: String, open: Character, close: Character) -> Int {
  var inString = false
  var escaped = false
  var delta = 0
  for character in line {
    if inString {
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        inString = false
      }
    } else if character == "\"" {
      inString = true
    } else if character == open {
      delta += 1
    } else if character == close {
      delta -= 1
    }
  }
  return delta
}

private func firstStringLiteral(in text: String) -> String? {
  guard let first = text.firstIndex(of: "\"") else {
    return nil
  }
  var value = ""
  var escaped = false
  var index = text.index(after: first)
  while index < text.endIndex {
    let character = text[index]
    if escaped {
      value.append(character)
      escaped = false
    } else if character == "\\" {
      escaped = true
    } else if character == "\"" {
      return value
    } else {
      value.append(character)
    }
    index = text.index(after: index)
  }
  return nil
}

private func callArguments(named name: String, in text: String) -> [String] {
  guard let range = text.range(of: "\(name)(") ?? text.range(of: ".\(name)(") else {
    return []
  }
  var index = range.upperBound
  var balance = 1
  var current = ""
  var arguments: [String] = []
  var inString = false
  var escaped = false
  while index < text.endIndex {
    let character = text[index]
    if inString {
      current.append(character)
      if escaped {
        escaped = false
      } else if character == "\\" {
        escaped = true
      } else if character == "\"" {
        inString = false
      }
    } else if character == "\"" {
      inString = true
      current.append(character)
    } else if character == "(" {
      balance += 1
      current.append(character)
    } else if character == ")" {
      balance -= 1
      if balance == 0 {
        let argument = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !argument.isEmpty {
          arguments.append(argument)
        }
        break
      }
      current.append(character)
    } else if character == ",", balance == 1 {
      let argument = current.trimmingCharacters(in: .whitespacesAndNewlines)
      if !argument.isEmpty {
        arguments.append(argument)
      }
      current = ""
    } else {
      current.append(character)
    }
    index = text.index(after: index)
  }
  return arguments
}

private func argumentValue(
  named label: String,
  inCallNamed callName: String,
  text: String
) -> String? {
  callArguments(named: callName, in: text).first { argument in
    argument.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("\(label):")
  }.map { argument in
    String(argument.dropFirst("\(label):".count)).trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

private func stripStringLiteralsAndComments(_ source: String) -> String {
  let characters = Array(source)
  var output: [Character] = []
  var index = 0
  while index < characters.count {
    if characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "/" {
      while index < characters.count, characters[index] != "\n" {
        output.append(" ")
        index += 1
      }
      continue
    }
    if characters[index] == "\"" {
      let isTriple = index + 2 < characters.count
        && characters[index + 1] == "\""
        && characters[index + 2] == "\""
      if isTriple {
        output.append(" ")
        output.append(" ")
        output.append(" ")
        index += 3
        while index < characters.count {
          if index + 2 < characters.count,
            characters[index] == "\"",
            characters[index + 1] == "\"",
            characters[index + 2] == "\""
          {
            output.append(" ")
            output.append(" ")
            output.append(" ")
            index += 3
            break
          }
          output.append(characters[index] == "\n" ? "\n" : " ")
          index += 1
        }
        continue
      }

      output.append(" ")
      index += 1
      var escaped = false
      while index < characters.count {
        let character = characters[index]
        output.append(character == "\n" ? "\n" : " ")
        index += 1
        if escaped {
          escaped = false
        } else if character == "\\" {
          escaped = true
        } else if character == "\"" {
          break
        }
      }
      continue
    }
    output.append(characters[index])
    index += 1
  }
  return String(output)
}

private func sanitizedIdentifier(_ name: String) -> String {
  let scalars = name.unicodeScalars.map { scalar -> String in
    CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
  }
  let identifier = scalars.joined()
  return identifier.isEmpty ? "BenchmarkSuite" : identifier
}
