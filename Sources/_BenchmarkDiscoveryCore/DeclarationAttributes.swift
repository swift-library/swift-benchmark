// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftParser
import SwiftSyntax

/// What a `@Suite`, `@Test` or `@Benchmark` attribute contributes to the
/// benchmark the bridge declares for it.
struct DeclarationAttribute: Equatable {
  var displayName: String?
  /// Whether the attribute itself enrolls the declaration: `@Benchmark`, or a
  /// `.benchmark(...)` trait.
  var isBenchmark: Bool
  /// Benchmark trait expressions, as source.
  var traits: [String]
  /// The `arguments:` collections, as source.
  var argumentExpressions: [String]
  /// A `Benchmark.Dimension(...)` expression from a `.dimension(...)` trait.
  var dimensionExpression: String?

  /// Reads a Swift Testing `@Suite` or `@Test` attribute. `.benchmark(configuration:)`
  /// becomes a `.configuration(...)` trait and each `.tags(...)` argument a
  /// `.tag(...)` trait; other Swift Testing traits have no benchmark meaning.
  init(testing attribute: AttributeSyntax) {
    let arguments = AttributeArguments(attribute)
    displayName = arguments.displayName
    isBenchmark = false
    traits = []
    argumentExpressions = arguments.collections.map(\.trimmedDescription)
    dimensionExpression = nil

    for trait in arguments.traits.compactMap(StaticMemberTrait.init) {
      switch trait.name {
      case "benchmark":
        isBenchmark = true
        if let configuration = trait.arguments.first(where: { $0.label?.text == "configuration" }) {
          traits.append(".configuration(\(configuration.expression.trimmedDescription))")
        }
      case "tags":
        traits += trait.arguments.compactMap { tagName($0.expression) }
          .map { ".tag(\(String(reflecting: $0)))" }
      default:
        break
      }
    }
  }

  /// Reads a `@Benchmark` attribute, whose traits are benchmark case traits
  /// already; `.dimension(...)` moves to the Dimension expression.
  init(benchmark attribute: AttributeSyntax) {
    let arguments = AttributeArguments(attribute)
    displayName = arguments.displayName
    isBenchmark = true
    traits = []
    argumentExpressions = arguments.collections.map(\.trimmedDescription)
    dimensionExpression = nil

    for expression in arguments.traits {
      if let trait = StaticMemberTrait(expression), trait.name == "dimension" {
        dimensionExpression = "Benchmark.Dimension(\(trait.arguments.trimmedDescription))"
      } else {
        traits.append(expression.trimmedDescription)
      }
    }
  }
}

/// The argument shape `@Suite`, `@Test` and `@Benchmark` share: an optional
/// display name literal, trait expressions, then `arguments:` collections.
private struct AttributeArguments {
  var displayName: String?
  var traits: [ExprSyntax] = []
  var collections: [ExprSyntax] = []

  init(_ attribute: AttributeSyntax) {
    guard case .argumentList(let list) = attribute.arguments else {
      return
    }
    for (offset, element) in list.enumerated() {
      if element.label?.text == "arguments" || (!collections.isEmpty && element.label == nil) {
        collections.append(element.expression)
      } else if element.label != nil {
        continue
      } else if offset == 0, let literal = element.expression.as(StringLiteralExprSyntax.self) {
        displayName = literal.representedLiteralValue
      } else {
        traits.append(element.expression)
      }
    }
  }
}

/// A trait written as a static member: `.name`, `.name(...)`, or the same
/// qualified by a type.
private struct StaticMemberTrait {
  var name: String
  var arguments: LabeledExprListSyntax

  init?(_ expression: ExprSyntax) {
    if let call = expression.as(FunctionCallExprSyntax.self),
      let member = call.calledExpression.as(MemberAccessExprSyntax.self)
    {
      name = member.declName.baseName.text
      arguments = call.arguments
    } else if let member = expression.as(MemberAccessExprSyntax.self) {
      name = member.declName.baseName.text
      arguments = []
    } else {
      return nil
    }
  }
}

/// The name of a Swift Testing tag written as a string literal or as a static
/// member such as `.parser` or `Tag.parser`.
private func tagName(_ expression: ExprSyntax) -> String? {
  if let literal = expression.as(StringLiteralExprSyntax.self) {
    return literal.representedLiteralValue
  }
  return expression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
}

extension AttributeListSyntax {
  /// The first attribute named `name`, written plainly or qualified by its
  /// module.
  func attribute(named name: String) -> AttributeSyntax? {
    for element in self {
      guard case .attribute(let attribute) = element else {
        continue
      }
      let written = attribute.attributeName.trimmedDescription
      if written == name || written.hasSuffix(".\(name)") {
        return attribute
      }
    }
    return nil
  }
}

extension DeclModifierListSyntax {
  var isPrivate: Bool {
    contains { [.keyword(.private), .keyword(.fileprivate)].contains($0.name.tokenKind) }
  }

  var isStatic: Bool {
    contains { [.keyword(.static), .keyword(.class)].contains($0.name.tokenKind) }
  }
}
