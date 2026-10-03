// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import SwiftParser
import SwiftSyntax
import _BenchmarkDiscoveryCore

public enum BenchmarkSyntaxDiscoveryToolDriver {
  public static func run(arguments: [String]) {
    do {
      try BenchmarkSyntaxDiscoveryCommand.run(arguments)
    } catch {
      fputs("BenchmarkSyntaxDiscoveryTool: \(error)\n", stderr)
      Foundation.exit(1)
    }
  }
}

enum BenchmarkSyntaxDiscoveryCommand {
  static func run(_ arguments: [String]) throws {
    guard arguments.first == "discover" else {
      throw ToolError.invalidArguments(
        "usage: BenchmarkSyntaxDiscoveryTool discover --targets-manifest <path> --work-directory <path> --output-plan <path>"
      )
    }

    let options = try DiscoverOptions(arguments: Array(arguments.dropFirst()))
    let manifestURL = URL(fileURLWithPath: options.targetsManifestPath)
    let manifestData = try Data(contentsOf: manifestURL)
    let manifest = try JSONDecoder().decode(TargetManifest.self, from: manifestData)
    let plan = try SyntaxDiscoveryPlanner(
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

struct SyntaxDiscoveryPlanner {
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
        let scan = try SyntaxSourceScanner(target: target).scan()
        diagnostics.append(contentsOf: scan.diagnostics)
        if !scan.suites.isEmpty {
          testingBridges.append(try writeTestingBridge(for: target, suites: scan.suites))
          continue
        }
        if !scan.nativeDeclarations.isEmpty {
          skippedTestTargets.append(target.name)
        }
        continue
      }

      let scan = try SyntaxSourceScanner(target: target).scan()
      diagnostics.append(contentsOf: scan.diagnostics)
      guard !scan.nativeDeclarations.isEmpty else {
        continue
      }

      guard !target.isExecutable else {
        skippedExecutableTargets.append(target.name)
        continue
      }

      nativeDiscoveries.append(
        contentsOf: scan.nativeDeclarations.map { declaration in
          NativeDiscoveryReference(
            moduleName: target.moduleName,
            targetName: target.name,
            typeName: declaration.typeName,
            discoveryTypeName: declaration.discoveryTypeName
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

    let discoveryExpressions =
      nativeDiscoveries.map {
        "\($0.moduleName).\($0.discoveryTypeName).self"
      }
      + testingBridges.map {
        "\($0.discoveryTypeName).self"
      }
    let hostSourcePath = try writeGeneratedBenchmarkHost(
      workDirectory: workDirectory,
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

  private func writeTestingBridge(
    for target: TargetDescription,
    suites: [DiscoveredSuite]
  ) throws -> TestingBridgeReference {
    let directory = workDirectory.appendingPathComponent("BenchmarkTestingBridge")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let discoveryName = "__BenchmarkTestingDiscovery_\(sanitizedIdentifier(target.name))"
    let outputURL = directory.appendingPathComponent("\(sanitizedIdentifier(target.name)).swift")
    let source = BridgeSourceGenerator(
      moduleName: target.moduleName,
      discoveryName: discoveryName,
      suites: suites
    ).render()
    try source.write(to: outputURL, atomically: true, encoding: .utf8)
    return TestingBridgeReference(
      moduleName: target.moduleName,
      targetName: target.name,
      discoveryTypeName: discoveryName,
      sourcePath: outputURL.path
    )
  }
}

private struct SyntaxScanResult {
  var nativeDeclarations: [SyntaxNativeDeclaration] = []
  var suites: [DiscoveredSuite] = []
  var diagnostics: [String] = []
}

private struct SyntaxNativeDeclaration {
  var typeName: String
  var discoveryTypeName: String
}

private struct SyntaxTypeDeclaration {
  enum Kind {
    case `struct`
    case `class`
    case actor
    case `enum`
  }

  var name: String
  var qualifiedName: String
  var nativeDiscoveryTypeName: String
  var kind: Kind
}

private struct SyntaxSuiteContext {
  var type: SyntaxTypeDeclaration
  var isEnrolled: Bool
  var suiteName: String
  var traits: [String]
  var cases: [DiscoveredCase]
}

private struct SyntaxAttributeInfo {
  var displayName: String?
  var hasBenchmark: Bool
  var argumentExpressions: [String]
  var dimensionExpression: String?
  var traits: [String]

  static var empty: SyntaxAttributeInfo {
    SyntaxAttributeInfo(
      displayName: nil,
      hasBenchmark: false,
      argumentExpressions: [],
      dimensionExpression: nil,
      traits: []
    )
  }
}

private struct SyntaxSourceScanner {
  var target: TargetDescription

  func scan() throws -> SyntaxScanResult {
    var result = SyntaxScanResult()
    for path in target.sourcePaths {
      let source = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
      let tree = Parser.parse(source: source)
      let converter = SourceLocationConverter(fileName: path, tree: tree)
      let visitor = SyntaxDiscoveryVisitor(
        targetName: target.name,
        filePath: path,
        converter: converter
      )
      visitor.walk(tree)
      result.nativeDeclarations.append(contentsOf: visitor.nativeDeclarations)
      result.suites.append(contentsOf: visitor.suites)
      result.diagnostics.append(contentsOf: visitor.diagnostics)
    }
    return result
  }
}

private final class SyntaxDiscoveryVisitor: SyntaxVisitor {
  let targetName: String
  let filePath: String
  let converter: SourceLocationConverter
  var nativeDeclarations: [SyntaxNativeDeclaration] = []
  var suites: [DiscoveredSuite] = []
  var diagnostics: [String] = []

  private var contexts: [SyntaxSuiteContext] = []

  init(
    targetName: String,
    filePath: String,
    converter: SourceLocationConverter
  ) {
    self.targetName = targetName
    self.filePath = filePath
    self.converter = converter
    super.init(viewMode: .sourceAccurate)
  }

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(
      name: node.name.text,
      kind: .struct,
      attributes: node.attributes
    )
    return .visitChildren
  }

  override func visitPost(_ node: StructDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(
      name: node.name.text,
      kind: .class,
      attributes: node.attributes
    )
    return .visitChildren
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(
      name: node.name.text,
      kind: .actor,
      attributes: node.attributes
    )
    return .visitChildren
  }

  override func visitPost(_ node: ActorDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    enterType(
      name: node.name.text,
      kind: .enum,
      attributes: node.attributes
    )
    return .visitChildren
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    leaveType()
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    scanFunction(node)
    return .skipChildren
  }

  private func enterType(
    name: String,
    kind: SyntaxTypeDeclaration.Kind,
    attributes: AttributeListSyntax
  ) {
    let qualifiedName = (contexts.last?.type.qualifiedName).map { "\($0).\(name)" } ?? name
    let discoveryTypeName =
      (contexts.last?.type.qualifiedName).map {
        "\($0).__BenchmarkDiscovery_\(sanitizedIdentifier(name))"
      } ?? "__BenchmarkDiscovery_\(sanitizedIdentifier(name))"
    let type = SyntaxTypeDeclaration(
      name: name,
      qualifiedName: qualifiedName,
      nativeDiscoveryTypeName: discoveryTypeName,
      kind: kind
    )

    if attribute(named: "BenchmarkSuite", in: attributes) != nil {
      nativeDeclarations.append(
        SyntaxNativeDeclaration(
          typeName: qualifiedName,
          discoveryTypeName: discoveryTypeName
        )
      )
    }

    let suiteInfo =
      attribute(named: "Suite", in: attributes)
      .map(attributeInfo(from:)) ?? .empty
    let inherited = contexts.last?.isEnrolled == true
    let isEnrolled = inherited || suiteInfo.hasBenchmark
    let suiteName = suiteInfo.displayName ?? qualifiedName
    let suiteTraits = (contexts.last?.traits ?? []) + suiteInfo.traits
    contexts.append(
      SyntaxSuiteContext(
        type: type,
        isEnrolled: isEnrolled,
        suiteName: suiteName,
        traits: suiteTraits,
        cases: []
      )
    )
  }

  private func leaveType() {
    guard let context = contexts.popLast(), !context.cases.isEmpty else {
      return
    }
    suites.append(
      DiscoveredSuite(
        name: context.suiteName,
        traits: context.traits,
        cases: context.cases
      )
    )
  }

  private func scanFunction(_ node: FunctionDeclSyntax) {
    let benchmarkAttribute = attribute(named: "Benchmark", in: node.attributes)
    let testAttribute = attribute(named: "Test", in: node.attributes)
    guard let bridgeAttribute = benchmarkAttribute ?? testAttribute else {
      return
    }

    let testInfo = attributeInfo(from: bridgeAttribute)
    let context = contexts.last
    let isNativeBenchmark = benchmarkAttribute != nil
    let isEnrolled = isNativeBenchmark || context?.isEnrolled == true || testInfo.hasBenchmark
    guard isEnrolled else {
      return
    }

    let location = node.funcKeyword.startLocation(converter: converter)
    let line = location.line
    let column = location.column
    let diagnosticPrefix = "\(filePath):\(line):\(column):"

    if isPrivate(node.modifiers) {
      diagnostics.append(
        "\(diagnosticPrefix) private/fileprivate benchmark declarations cannot be bridged from generated source; make them internal or use @BenchmarkSuite/@Benchmark for same-scope discovery."
      )
      return
    }
    let parameterCount = node.signature.parameterClause.parameters.count
    if !testInfo.argumentExpressions.isEmpty, parameterCount == 0 {
      diagnostics.append(
        "\(diagnosticPrefix) parameterized benchmark declarations require at least one function parameter."
      )
      return
    }
    if testInfo.argumentExpressions.count > 2 {
      diagnostics.append(
        "\(diagnosticPrefix) benchmark argument discovery currently supports one collection, two collections, or zip(...)."
      )
      return
    }
    let argumentBinding = invocationBinding(
      parameterCount: parameterCount,
      argumentExpressions: testInfo.argumentExpressions
    )
    if !testInfo.argumentExpressions.isEmpty, argumentBinding == nil {
      diagnostics.append(
        "\(diagnosticPrefix) benchmark argument count does not match the function parameters."
      )
      return
    }
    if testInfo.argumentExpressions.isEmpty,
      testInfo.dimensionExpression == nil,
      !node.signature.parameterClause.parameters.isEmpty
    {
      diagnostics.append(
        "\(diagnosticPrefix) parameterized benchmark declarations require arguments: or .dimension(sizes:)."
      )
      return
    }
    if testInfo.dimensionExpression != nil, parameterCount > 1 {
      diagnostics.append(
        "\(diagnosticPrefix) Dimension benchmark declarations support at most one Benchmark.Scale parameter."
      )
      return
    }
    if context?.type.kind == .enum, !isStatic(node.modifiers) {
      diagnostics.append(
        "\(diagnosticPrefix) instance @Test(.benchmark) methods in enum suites cannot be constructed by the BenchmarkTesting bridge."
      )
      return
    }
    if context?.type.kind == .actor, !isStatic(node.modifiers) {
      diagnostics.append(
        "\(diagnosticPrefix) instance @Test(.benchmark) methods in actor suites cannot be constructed by the BenchmarkTesting bridge."
      )
      return
    }

    let discovered = DiscoveredCase(
      name: testInfo.displayName ?? node.name.text,
      traits: testInfo.traits,
      sourceLocation: BenchmarkSourceLocationLiteral(
        fileID: "\(targetName)/\(URL(fileURLWithPath: filePath).lastPathComponent)",
        filePath: filePath,
        line: line,
        column: column
      ),
      argumentExpressions: testInfo.argumentExpressions,
      closureParameters: argumentBinding?.closureParameters ?? [],
      dimensionExpression: testInfo.dimensionExpression,
      invocation: invocationExpression(
        for: node,
        suiteType: context?.type,
        argumentValues: argumentBinding?.invocationArguments
          ?? (testInfo.dimensionExpression != nil && parameterCount == 1
            ? ["__benchmarkScale"] : [])
      )
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
  }

  private func invocationExpression(
    for node: FunctionDeclSyntax,
    suiteType: SyntaxTypeDeclaration?,
    argumentValues: [String] = []
  ) -> String {
    let effectPrefix =
      "\(node.signature.effectSpecifiers?.throwsClause == nil ? "" : "try ")\(node.signature.effectSpecifiers?.asyncSpecifier == nil ? "" : "await ")"
    let call = "\(node.name.text)(\(callArguments(for: node, values: argumentValues)))"
    guard let suiteType else {
      return "\(effectPrefix)\(call)"
    }
    if isStatic(node.modifiers) {
      return "\(effectPrefix)\(suiteType.qualifiedName).\(call)"
    }
    return """
      var suite = \(suiteType.qualifiedName)()
      \(effectPrefix)suite.\(call)
      """
  }

  private func callArguments(for node: FunctionDeclSyntax, values: [String]) -> String {
    zip(node.signature.parameterClause.parameters, values)
      .map { parameter, value in "\(callLabel(parameter))\(value)" }
      .joined(separator: ", ")
  }
}

private func attribute(
  named name: String,
  in attributes: AttributeListSyntax
) -> AttributeSyntax? {
  attributes.compactMap { element -> AttributeSyntax? in
    guard case .attribute(let attribute) = element else {
      return nil
    }
    let trimmed = attribute.attributeName.trimmedDescription
    return trimmed == name || trimmed.hasSuffix(".\(name)") ? attribute : nil
  }.first
}

private func attributeInfo(from attribute: AttributeSyntax) -> SyntaxAttributeInfo {
  let text = attribute.trimmedDescription
  return SyntaxAttributeInfo(
    displayName: firstStringLiteral(in: text),
    hasBenchmark: containsBenchmarkTrait(text),
    argumentExpressions: benchmarkArgumentExpressions(from: attribute),
    dimensionExpression: benchmarkDimensionExpression(from: attribute),
    traits: benchmarkTraits(from: text) + tagTraits(from: text)
  )
}

private func isPrivate(_ modifiers: DeclModifierListSyntax) -> Bool {
  modifiers.contains { modifier in
    modifier.name.tokenKind == .keyword(.private)
      || modifier.name.tokenKind == .keyword(.fileprivate)
  }
}

private func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
  modifiers.contains { modifier in
    modifier.name.tokenKind == .keyword(.static)
      || modifier.name.tokenKind == .keyword(.class)
  }
}

private struct InvocationBinding {
  var closureParameters: [String]
  var invocationArguments: [String]
}

private func invocationBinding(
  parameterCount: Int,
  argumentExpressions: [String]
) -> InvocationBinding? {
  guard !argumentExpressions.isEmpty else {
    return nil
  }
  if argumentExpressions.count == 1,
    argumentExpressions[0].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("zip("),
    parameterCount == 2
  {
    return InvocationBinding(
      closureParameters: ["__benchmarkArgument0", "__benchmarkArgument1"],
      invocationArguments: ["__benchmarkArgument0", "__benchmarkArgument1"]
    )
  }
  if argumentExpressions.count == 1, parameterCount > 1 {
    return InvocationBinding(
      closureParameters: ["__benchmarkArguments"],
      invocationArguments: (0..<parameterCount).map { "__benchmarkArguments.\($0)" }
    )
  }
  guard argumentExpressions.count == parameterCount else {
    return nil
  }
  let parameters = (0..<parameterCount).map { "__benchmarkArgument\($0)" }
  return InvocationBinding(closureParameters: parameters, invocationArguments: parameters)
}

private func callLabel(_ parameter: FunctionParameterSyntax) -> String {
  parameter.firstName.text == "_" ? "" : "\(parameter.firstName.text): "
}

private func containsBenchmarkTrait(_ text: String) -> Bool {
  text.contains(".benchmark") || text.contains("benchmark(")
}

private func benchmarkArgumentExpressions(from attribute: AttributeSyntax) -> [String] {
  guard case .argumentList(let list) = attribute.arguments else {
    return []
  }
  var result: [String] = []
  var collecting = false
  for element in list {
    if element.label?.text == "arguments" {
      result.append(element.expression.trimmedDescription)
      collecting = true
      continue
    }
    if collecting, element.label == nil {
      result.append(element.expression.trimmedDescription)
      continue
    }
    if collecting {
      break
    }
  }
  return result
}

private func benchmarkDimensionExpression(from attribute: AttributeSyntax) -> String? {
  guard case .argumentList(let list) = attribute.arguments else {
    return nil
  }
  for element in list {
    let text = element.expression.trimmedDescription
    if text.hasPrefix(".dimension(") {
      return "Benchmark.Dimension\(text.dropFirst(".dimension".count))"
    }
  }
  return nil
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
