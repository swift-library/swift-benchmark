// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import SwiftParser
import SwiftSyntax

/// What a target's sources declare for benchmark discovery.
struct ScanResult {
  /// `@BenchmarkSuite` types, discoverable through the type their macro
  /// declares.
  var nativeDeclarations: [NativeDeclaration] = []
  /// Enrolled Swift Testing suites and `@Benchmark` functions, which a test
  /// target's bridge declares again as benchmark suites.
  var suites: [DiscoveredSuite] = []
  var diagnostics: [String] = []
}

struct NativeDeclaration: Equatable {
  var typeName: String
  var discoveryTypeName: String
}

/// Parses a target's sources with SwiftSyntax.
struct SourceScanner {
  var target: TargetDescription

  func scan() throws -> ScanResult {
    let files = try target.sourcePaths.map { path in
      (path: path, tree: Parser.parse(source: try String(contentsOfFile: path, encoding: .utf8)))
    }
    // An extension can live in another file than its type, so every type is
    // indexed before functions are resolved against their enclosing type.
    var types: [String: DeclaredType] = [:]
    for file in files {
      let indexer = TypeIndexer()
      indexer.walk(file.tree)
      types.merge(indexer.types) { first, _ in first }
    }

    var result = ScanResult()
    var suites = SuiteList()
    for file in files {
      let visitor = DeclarationVisitor(
        target: target, filePath: file.path, tree: file.tree, types: types)
      visitor.walk(file.tree)
      result.nativeDeclarations += visitor.nativeDeclarations
      result.diagnostics += visitor.diagnostics
      for entry in visitor.cases {
        suites.add(entry)
      }
    }
    result.suites = suites.suites
    return result
  }
}

/// A type declared in the target.
struct DeclaredType {
  enum Kind {
    case `struct`
    case `class`
    case actor
    case `enum`
  }

  var name: String
  /// The qualified name of the type or extended type it is declared in.
  var parentName: String?
  var kind: Kind
  var isPrivate: Bool
  /// The type's Swift Testing `@Suite` attribute.
  var suite: DeclarationAttribute?

  var qualifiedName: String {
    parentName.map { "\($0).\(name)" } ?? name
  }
}

/// Walks declarations while tracking the qualified name of the enclosing
/// type; an extension's members belong to the extended type. Bodies of
/// functions, initializers, properties and closures are skipped, since what
/// they declare is local and generated source cannot refer to it.
class ScopedVisitor: SyntaxVisitor {
  private(set) var scope: [String] = []

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  func didEnter(_ type: DeclaredType, attributes: AttributeListSyntax) {}

  func visitFunction(_ node: FunctionDeclSyntax) {}

  override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name, .struct, node.attributes, node.modifiers)
  }

  override func visitPost(_ node: StructDeclSyntax) {
    scope.removeLast()
  }

  override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name, .class, node.attributes, node.modifiers)
  }

  override func visitPost(_ node: ClassDeclSyntax) {
    scope.removeLast()
  }

  override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name, .actor, node.attributes, node.modifiers)
  }

  override func visitPost(_ node: ActorDeclSyntax) {
    scope.removeLast()
  }

  override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
    enter(node.name, .enum, node.attributes, node.modifiers)
  }

  override func visitPost(_ node: EnumDeclSyntax) {
    scope.removeLast()
  }

  override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
    scope.append(Self.typeName(node.extendedType))
    return .visitChildren
  }

  override func visitPost(_ node: ExtensionDeclSyntax) {
    scope.removeLast()
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    visitFunction(node)
    return .skipChildren
  }

  override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
    .skipChildren
  }

  private func enter(
    _ name: TokenSyntax,
    _ kind: DeclaredType.Kind,
    _ attributes: AttributeListSyntax,
    _ modifiers: DeclModifierListSyntax
  ) -> SyntaxVisitorContinueKind {
    let type = DeclaredType(
      name: name.text,
      parentName: scope.last,
      kind: kind,
      isPrivate: modifiers.isPrivate,
      suite: attributes.attribute(named: "Suite").map(DeclarationAttribute.init(testing:))
    )
    scope.append(type.qualifiedName)
    didEnter(type, attributes: attributes)
    return .visitChildren
  }

  private static func typeName(_ type: TypeSyntax) -> String {
    if let identifier = type.as(IdentifierTypeSyntax.self) {
      return identifier.name.text
    }
    if let member = type.as(MemberTypeSyntax.self) {
      return "\(typeName(member.baseType)).\(member.name.text)"
    }
    return type.trimmedDescription
  }
}

private final class TypeIndexer: ScopedVisitor {
  private(set) var types: [String: DeclaredType] = [:]

  override func didEnter(_ type: DeclaredType, attributes: AttributeListSyntax) {
    if types[type.qualifiedName] == nil {
      types[type.qualifiedName] = type
    }
  }
}

/// The suite a member of a type belongs to. Swift Testing suites inherit
/// enrollment and traits from the types they are nested in.
private struct SuiteContext {
  var type: DeclaredType
  var name: String
  var isEnrolled = false
  var traits: [String] = []
  /// Whether generated source can name the type: neither it nor an enclosing
  /// type is private.
  var isAccessible = true
}

private final class DeclarationVisitor: ScopedVisitor {
  struct Entry {
    var suiteKey: String
    var suiteName: String
    var suiteTraits: [String]
    var benchmarkCase: DiscoveredCase
  }

  private let target: TargetDescription
  private let filePath: String
  private let converter: SourceLocationConverter
  private let types: [String: DeclaredType]
  private(set) var nativeDeclarations: [NativeDeclaration] = []
  private(set) var cases: [Entry] = []
  private(set) var diagnostics: [String] = []

  init(
    target: TargetDescription,
    filePath: String,
    tree: SourceFileSyntax,
    types: [String: DeclaredType]
  ) {
    self.target = target
    self.filePath = filePath
    self.converter = SourceLocationConverter(fileName: filePath, tree: tree)
    self.types = types
    super.init()
  }

  override func didEnter(_ type: DeclaredType, attributes: AttributeListSyntax) {
    guard attributes.attribute(named: "BenchmarkSuite") != nil else {
      return
    }
    let discoveryName = "__BenchmarkDiscovery_\(sanitizedIdentifier(type.name))"
    nativeDeclarations.append(
      NativeDeclaration(
        typeName: type.qualifiedName,
        discoveryTypeName: type.parentName.map { "\($0).\(discoveryName)" } ?? discoveryName
      )
    )
  }

  override func visitFunction(_ node: FunctionDeclSyntax) {
    let attribute: DeclarationAttribute
    if let benchmark = node.attributes.attribute(named: "Benchmark") {
      attribute = DeclarationAttribute(benchmark: benchmark)
    } else if let test = node.attributes.attribute(named: "Test") {
      attribute = DeclarationAttribute(testing: test)
    } else {
      return
    }

    let enclosingName = scope.last
    let context = enclosingName.flatMap(suiteContext)
    guard attribute.isBenchmark || context?.isEnrolled == true else {
      return
    }

    let location = node.funcKeyword.startLocation(converter: converter)
    let parameterCount = node.signature.parameterClause.parameters.count
    let binding = invocationBinding(
      parameterCount: parameterCount,
      argumentExpressions: attribute.argumentExpressions
    )
    if let problem = unsupported(
      node, attribute: attribute, enclosingName: enclosingName, context: context,
      binding: binding)
    {
      diagnostics.append("\(filePath):\(location.line):\(location.column): \(problem)")
      return
    }

    let benchmarkCase = DiscoveredCase(
      name: attribute.displayName ?? node.name.text,
      traits: attribute.traits,
      sourceLocation: BenchmarkSourceLocationLiteral(
        fileID: "\(target.moduleName)/\(URL(fileURLWithPath: filePath).lastPathComponent)",
        filePath: filePath,
        line: location.line,
        column: location.column
      ),
      argumentExpressions: attribute.argumentExpressions,
      closureParameters: binding?.closureParameters ?? [],
      dimensionExpression: attribute.dimensionExpression,
      invocation: invocation(
        of: node,
        in: context?.type,
        argumentValues: binding?.invocationArguments
          ?? (attribute.dimensionExpression != nil && parameterCount == 1
            ? ["__benchmarkScale"] : [])
      )
    )
    cases.append(
      Entry(
        suiteKey: context?.type.qualifiedName ?? "",
        suiteName: context?.name ?? target.name,
        suiteTraits: context?.traits ?? [],
        benchmarkCase: benchmarkCase
      )
    )
  }

  private func suiteContext(_ typeName: String) -> SuiteContext? {
    guard let type = types[typeName] else {
      return nil
    }
    var context = SuiteContext(type: type, name: type.suite?.displayName ?? typeName)
    var prefix: String?
    for component in typeName.split(separator: ".") {
      let name = prefix.map { "\($0).\(component)" } ?? String(component)
      prefix = name
      guard let enclosing = types[name] else {
        continue
      }
      context.isEnrolled = context.isEnrolled || enclosing.suite?.isBenchmark == true
      context.traits += enclosing.suite?.traits ?? []
      context.isAccessible = context.isAccessible && !enclosing.isPrivate
    }
    return context
  }

  /// Why the bridge cannot call the declaration, if it cannot.
  private func unsupported(
    _ node: FunctionDeclSyntax,
    attribute: DeclarationAttribute,
    enclosingName: String?,
    context: SuiteContext?,
    binding: InvocationBinding?
  ) -> String? {
    let parameterCount = node.signature.parameterClause.parameters.count
    let arguments = attribute.argumentExpressions
    if let enclosingName, context == nil {
      return
        "benchmark declarations in an extension of `\(enclosingName)` need the type to be declared in the same target."
    }
    if node.modifiers.isPrivate {
      return
        "private/fileprivate benchmark declarations cannot be bridged from generated source; make them internal or use @BenchmarkSuite/@Benchmark for same-scope discovery."
    }
    if context?.isAccessible == false {
      return
        "benchmark declarations in private/fileprivate types cannot be bridged from generated source; make the types internal."
    }
    if !arguments.isEmpty, parameterCount == 0 {
      return "parameterized benchmark declarations require at least one function parameter."
    }
    if arguments.count > 2 {
      return
        "benchmark argument discovery currently supports one collection, two collections, or zip(...)."
    }
    if !arguments.isEmpty, binding == nil {
      return "benchmark argument count does not match the function parameters."
    }
    if arguments.isEmpty, attribute.dimensionExpression == nil, parameterCount > 0 {
      return
        "parameterized benchmark declarations require arguments: or .dimension(sizes:)."
    }
    if attribute.dimensionExpression != nil, parameterCount > 1 {
      return "Dimension benchmark declarations support at most one Benchmark.Scale parameter."
    }
    if context?.type.kind == .enum, !node.modifiers.isStatic {
      return
        "instance @Test(.benchmark) methods in enum suites cannot be constructed by the BenchmarkTesting bridge."
    }
    if context?.type.kind == .actor, !node.modifiers.isStatic {
      return
        "instance @Test(.benchmark) methods in actor suites cannot be constructed by the BenchmarkTesting bridge."
    }
    return nil
  }

  private func invocation(
    of node: FunctionDeclSyntax,
    in suiteType: DeclaredType?,
    argumentValues: [String]
  ) -> String {
    let effects = node.signature.effectSpecifiers
    let effectPrefix =
      (effects?.throwsClause == nil ? "" : "try ")
      + (effects?.asyncSpecifier == nil ? "" : "await ")
    let callArguments = zip(node.signature.parameterClause.parameters, argumentValues)
      .map { parameter, value in
        parameter.firstName.text == "_" ? value : "\(parameter.firstName.text): \(value)"
      }
      .joined(separator: ", ")
    let call = "\(node.name.text)(\(callArguments))"
    guard let suiteType else {
      return "\(effectPrefix)\(call)"
    }
    if node.modifiers.isStatic {
      return "\(effectPrefix)\(suiteType.qualifiedName).\(call)"
    }
    let binding =
      node.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) } ? "var" : "let"
    return """
      \(binding) suite = \(suiteType.qualifiedName)()
      \(effectPrefix)suite.\(call)
      """
  }
}

/// How one argument row reaches the declared function's parameters.
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
  if argumentExpressions.count == 1, argumentExpressions[0].hasPrefix("zip("),
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

/// Suites in the order their first case appears; cases declared in a type's
/// extensions join the type's suite.
private struct SuiteList {
  private var keys: [String] = []
  private var suitesByKey: [String: DiscoveredSuite] = [:]

  var suites: [DiscoveredSuite] {
    keys.compactMap { suitesByKey[$0] }
  }

  mutating func add(_ entry: DeclarationVisitor.Entry) {
    if suitesByKey[entry.suiteKey] == nil {
      keys.append(entry.suiteKey)
      suitesByKey[entry.suiteKey] = DiscoveredSuite(
        name: entry.suiteName, traits: entry.suiteTraits, cases: [])
    }
    suitesByKey[entry.suiteKey]?.cases.append(entry.benchmarkCase)
  }
}
