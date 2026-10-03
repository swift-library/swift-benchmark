// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import Foundation
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct BenchmarkMacroPlugin: CompilerPlugin {
  let providingMacros: [Macro.Type] = [
    BenchmarkSuiteMacro.self,
    BenchmarkMacro.self,
  ]
}

public struct BenchmarkSuiteMacro: MemberMacro, ExtensionMacro, PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingMembersOf declaration: some DeclGroupSyntax,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    let suiteName = suiteNameExpression(from: node, declaration: declaration)
    let suiteTraits = traitArrayExpression(from: node)
    let benchmarkExpressions = declaration.memberBlock.members.compactMap { member -> String? in
      guard let function = member.decl.as(FunctionDeclSyntax.self),
        hasBenchmarkAttribute(function)
      else {
        return nil
      }
      let caseName = benchmarkNameExpression(from: function)
      let benchmarkAttribute = function.attributes.compactMap(benchmarkAttribute).first
      let caseTraits = benchmarkAttribute.map(traitArrayExpression(from:)) ?? "[]"
      let target = isStatic(function) ? "Self." : "Self()."
      let parameters = Array(function.signature.parameterClause.parameters)
      if let benchmarkAttribute,
        let arguments = argumentExpressions(from: benchmarkAttribute),
        !arguments.isEmpty
      {
        return parameterizedBenchmarkExpression(
          caseName: caseName,
          caseTraits: caseTraits,
          arguments: arguments,
          target: target,
          function: function,
          parameters: parameters
        )
      }
      if parameters.isEmpty {
        let invocation =
          "\(throwingPrefix(function))\(asyncPrefix(function))\(target)\(function.name.text)()"
        return """
              Benchmark(\(caseName), traits: \(caseTraits)) {
                \(invocation)
              }
          """
      }
      guard parameters.count == 1,
        let attribute = benchmarkAttribute,
        let dimension = dimensionExpression(from: attribute)
      else {
        return nil
      }
      let parameter = parameters[0]
      let valueName = localParameterName(parameter)
      let label = callLabel(parameter)
      let invocation =
        "\(throwingPrefix(function))\(asyncPrefix(function))\(target)\(function.name.text)(\(label)\(valueName))"
      return """
            Benchmark(\(caseName), dimension: \(dimension), traits: \(caseTraits), input: { $0 }) { \(valueName) in
              \(invocation)
            }
        """
    }
    let body =
      benchmarkExpressions.isEmpty
      ? "" : "\n\(benchmarkExpressions.joined(separator: "\n"))\n      "

    return [
      """
      public static var __benchmarkSuites: [BenchmarkSuite] {
        [
          BenchmarkSuite(\(raw: suiteName), traits: \(raw: suiteTraits)) {\(raw: body)}
        ]
      }
      """
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    guard let named = declaration.asProtocol(NamedDeclSyntax.self) else {
      return []
    }
    let typeName = named.name.text
    return [
      """
      public enum __BenchmarkDiscovery_\(raw: sanitizedIdentifier(typeName)): _BenchmarkDiscovery {
        public static var __benchmarkSuites: [BenchmarkSuite] {
          \(raw: typeName).__benchmarkSuites
        }
      }
      """
    ]
  }

  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingExtensionsOf type: some TypeSyntaxProtocol,
    conformingTo protocols: [TypeSyntax],
    in context: some MacroExpansionContext
  ) throws -> [ExtensionDeclSyntax] {
    [try ExtensionDeclSyntax("extension \(type.trimmed): _BenchmarkDiscovery {}")]
  }
}

public struct BenchmarkMacro: PeerMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingPeersOf declaration: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [DeclSyntax] {
    []
  }
}

private func suiteNameExpression(
  from attribute: AttributeSyntax,
  declaration: some DeclGroupSyntax
) -> String {
  if let expression = parsedMacroArguments(from: attribute).name {
    return expression.trimmedDescription
  }
  if let named = declaration.asProtocol(NamedDeclSyntax.self) {
    return String(reflecting: named.name.text)
  }
  return "\"BenchmarkSuite\""
}

private func benchmarkNameExpression(from function: FunctionDeclSyntax) -> String {
  guard let attribute = function.attributes.compactMap(benchmarkAttribute).first,
    let expression = parsedMacroArguments(from: attribute).name
  else {
    return String(reflecting: function.name.text)
  }
  return expression.trimmedDescription
}

private func traitArrayExpression(from attribute: AttributeSyntax) -> String {
  let traits = parsedMacroArguments(from: attribute).traits
  guard !traits.isEmpty else {
    return "[]"
  }
  return "[\(traits.map(\.trimmedDescription).joined(separator: ", "))]"
}

private func dimensionExpression(from attribute: AttributeSyntax) -> String? {
  for expression in parsedMacroArguments(from: attribute).traits {
    let text = expression.trimmedDescription
    if text.hasPrefix(".dimension(") {
      return "Benchmark.Dimension\(text.dropFirst(".dimension".count))"
    }
  }
  return nil
}

private func parameterizedBenchmarkExpression(
  caseName: String,
  caseTraits: String,
  arguments: [String],
  target: String,
  function: FunctionDeclSyntax,
  parameters: [FunctionParameterSyntax]
) -> String? {
  guard !parameters.isEmpty else {
    return nil
  }
  let argumentList = arguments.joined(separator: ", ")
  let closureParameters: [String]
  let invocationArguments: [String]
  if arguments.count == 1,
    arguments[0].trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("zip("),
    parameters.count == 2
  {
    closureParameters = ["__benchmarkArgument0", "__benchmarkArgument1"]
    invocationArguments = closureParameters
  } else if arguments.count == 1, parameters.count > 1 {
    closureParameters = ["__benchmarkArguments"]
    invocationArguments = parameters.indices.map { "__benchmarkArguments.\($0)" }
  } else {
    guard arguments.count == parameters.count else {
      return nil
    }
    closureParameters = parameters.indices.map { "__benchmarkArgument\($0)" }
    invocationArguments = closureParameters
  }

  let callArguments = zip(parameters, invocationArguments)
    .map { parameter, value in "\(callLabel(parameter))\(value)" }
    .joined(separator: ", ")
  let invocation =
    "\(throwingPrefix(function))\(asyncPrefix(function))\(target)\(function.name.text)(\(callArguments))"
  return """
        Benchmark(\(caseName), arguments: \(argumentList), traits: \(caseTraits)) { \(closureParameters.joined(separator: ", ")) in
          \(invocation)
        }
    """
}

private func argumentExpressions(from attribute: AttributeSyntax) -> [String]? {
  parsedMacroArguments(from: attribute).arguments.map { $0.map(\.trimmedDescription) }
}

private struct ParsedMacroArguments {
  var name: ExprSyntax?
  var traits: [ExprSyntax]
  var arguments: [ExprSyntax]?
}

private func parsedMacroArguments(from attribute: AttributeSyntax) -> ParsedMacroArguments {
  guard let arguments = attribute.arguments else {
    return ParsedMacroArguments(name: nil, traits: [], arguments: nil)
  }
  switch arguments {
  case .argumentList(let list):
    var expressions: [ExprSyntax] = []
    var argumentExpressions: [ExprSyntax]?
    var name: ExprSyntax?
    var sawName = false
    for element in list {
      if element.label?.text == "arguments" {
        argumentExpressions = [element.expression]
        continue
      }
      if argumentExpressions != nil, element.label == nil {
        argumentExpressions?.append(element.expression)
        continue
      }
      if !sawName, element.label == nil, isNameExpression(element.expression) {
        name = element.expression
        sawName = true
        continue
      }
      expressions.append(element.expression)
    }
    if !sawName {
      name = nil
    }
    return ParsedMacroArguments(name: name, traits: expressions, arguments: argumentExpressions)
  default:
    return ParsedMacroArguments(name: nil, traits: [], arguments: nil)
  }
}

private func isNameExpression(_ expression: ExprSyntax) -> Bool {
  expression.as(StringLiteralExprSyntax.self) != nil
}

private func hasBenchmarkAttribute(_ function: FunctionDeclSyntax) -> Bool {
  function.attributes.contains { benchmarkAttribute($0) != nil }
}

private func benchmarkAttribute(_ element: AttributeListSyntax.Element) -> AttributeSyntax? {
  guard case .attribute(let attribute) = element,
    attribute.attributeName.trimmedDescription == "Benchmark"
  else {
    return nil
  }
  return attribute
}

private func isStatic(_ function: FunctionDeclSyntax) -> Bool {
  function.modifiers.contains { modifier in
    modifier.name.tokenKind == .keyword(.static) || modifier.name.tokenKind == .keyword(.class)
  }
}

private func throwingPrefix(_ function: FunctionDeclSyntax) -> String {
  function.signature.effectSpecifiers?.throwsClause == nil ? "" : "try "
}

private func asyncPrefix(_ function: FunctionDeclSyntax) -> String {
  function.signature.effectSpecifiers?.asyncSpecifier == nil ? "" : "await "
}

private func localParameterName(_ parameter: FunctionParameterSyntax) -> String {
  if let secondName = parameter.secondName?.text {
    return secondName
  }
  let firstName = parameter.firstName.text
  return firstName == "_" ? "input" : firstName
}

private func callLabel(_ parameter: FunctionParameterSyntax) -> String {
  let firstName = parameter.firstName.text
  return firstName == "_" ? "" : "\(firstName): "
}

private func sanitizedIdentifier(_ name: String) -> String {
  let scalars = name.unicodeScalars.map { scalar -> String in
    CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : "_"
  }
  let identifier = scalars.joined()
  return identifier.isEmpty ? "BenchmarkSuite" : identifier
}
