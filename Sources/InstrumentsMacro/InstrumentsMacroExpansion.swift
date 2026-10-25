// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

enum InstrumentsMacroError: Error, CustomStringConvertible {
  case missingSpanName
  case missingSpanBody
  case missingEventName
  case unexpectedArgumentLabel(String)
  case duplicateArgumentLabel(String)
  case unsupportedAttachedDeclaration(String)
  case attachedMacroRequiresBody(String)
  case missingInitializerContext(String)

  var description: String {
    switch self {
    case .missingSpanName:
      return "span macro requires a static name argument."
    case .missingSpanBody:
      return "span macro requires a trailing closure body."
    case .missingEventName:
      return "event macro requires a static name argument."
    case .unexpectedArgumentLabel(let label):
      return "Unexpected Instruments macro argument label: \(label)"
    case .duplicateArgumentLabel(let label):
      return "Duplicate Instruments macro argument label: \(label)"
    case .unsupportedAttachedDeclaration(let attribute):
      return "@\(attribute) can only instrument functions and initializers with bodies."
    case .attachedMacroRequiresBody(let attribute):
      return "@\(attribute) requires a function or initializer body to instrument."
    case .missingInitializerContext(let attribute):
      return
        "@\(attribute) on an initializer requires a containing type to infer a span name. Use @Span(\"Type.init(...)\") to provide an explicit name."
    }
  }
}

enum InstrumentsMacroExpansion {
  static func parseSpanArguments(
    from arguments: [LabeledExprSyntax]
  ) throws -> (nameExpr: ExprSyntax, attributesExpr: ExprSyntax) {
    guard let nameExpr = arguments.first?.expression else {
      throw InstrumentsMacroError.missingSpanName
    }

    var attributesExpr: ExprSyntax = ".empty"
    for argument in arguments.dropFirst() {
      switch argument.label?.text {
      case "attributes":
        if attributesExpr.description != ".empty" {
          throw InstrumentsMacroError.duplicateArgumentLabel("attributes")
        }
        attributesExpr = argument.expression
      case let label?:
        throw InstrumentsMacroError.unexpectedArgumentLabel(label)
      case nil:
        throw InstrumentsMacroError.unexpectedArgumentLabel("<none>")
      }
    }

    return (nameExpr, attributesExpr)
  }

  static func parseEventArguments(
    from arguments: [LabeledExprSyntax]
  ) throws -> (nameExpr: ExprSyntax, attributesExpr: ExprSyntax) {
    guard let nameExpr = arguments.first?.expression else {
      throw InstrumentsMacroError.missingEventName
    }

    var attributesExpr: ExprSyntax = ".empty"
    for argument in arguments.dropFirst() {
      switch argument.label?.text {
      case "attributes":
        if attributesExpr.description != ".empty" {
          throw InstrumentsMacroError.duplicateArgumentLabel("attributes")
        }
        attributesExpr = argument.expression
      case let label?:
        throw InstrumentsMacroError.unexpectedArgumentLabel(label)
      case nil:
        throw InstrumentsMacroError.unexpectedArgumentLabel("<none>")
      }
    }

    return (nameExpr, attributesExpr)
  }

  static func makeSpanExpression(
    from node: some FreestandingMacroExpansionSyntax,
    invocation: String
  ) throws -> ExprSyntax {
    let parsed = try parseSpanArguments(from: Array(node.arguments))
    guard let closure = node.trailingClosure else {
      throw InstrumentsMacroError.missingSpanBody
    }
    let loweredClosure = try NestedInstrumentsMacroLowerer().lower(closure)

    return """
      {
        let __instrumentsRecorder = Instruments.current
        let __instrumentsToken = __instrumentsRecorder.beginSpan(\(parsed.nameExpr), attributes: \(parsed.attributesExpr))
        defer {
          __instrumentsRecorder.endSpan(__instrumentsToken)
        }
        return \(raw: invocation)\(loweredClosure)()
      }()
      """
  }

  static func makeEventExpression(
    from node: some FreestandingMacroExpansionSyntax
  ) throws -> ExprSyntax {
    let parsed = try parseEventArguments(from: Array(node.arguments))
    return
      "Instruments.current.recordEvent(\(parsed.nameExpr), attributes: \(parsed.attributesExpr))"
  }

  static func spanNameExpression(
    from attribute: AttributeSyntax,
    defaultName: String
  ) throws -> ExprSyntax {
    guard let arguments = attribute.arguments else {
      return ExprSyntax(literal: defaultName)
    }

    switch arguments {
    case .argumentList(let argumentList):
      guard let first = argumentList.first else {
        return ExprSyntax(literal: defaultName)
      }
      return first.expression
    default:
      throw InstrumentsMacroError.unexpectedArgumentLabel("<attribute>")
    }
  }

  static func instrumentedBody(
    attribute: AttributeSyntax,
    declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    explicitAttributeName: String?,
    defaultSpanName: String,
    context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    if let functionDecl = declaration.as(FunctionDeclSyntax.self) {
      return try instrumentedFunctionBody(
        attribute: attribute,
        functionDecl: functionDecl,
        explicitAttributeName: explicitAttributeName,
        defaultSpanName: defaultSpanName
      )
    }

    if let initializerDecl = declaration.as(InitializerDeclSyntax.self) {
      let defaultInitializerSpanName: String
      if explicitAttributeName == nil {
        guard let typeName = containingTypeName(in: context) else {
          throw InstrumentsMacroError.missingInitializerContext("Instrumented")
        }
        defaultInitializerSpanName = initializerSpanName(for: initializerDecl, typeName: typeName)
      } else {
        defaultInitializerSpanName = defaultSpanName
      }

      return try instrumentedInitializerBody(
        attribute: attribute,
        initializerDecl: initializerDecl,
        explicitAttributeName: explicitAttributeName,
        defaultSpanName: defaultInitializerSpanName
      )
    }

    throw InstrumentsMacroError.unsupportedAttachedDeclaration(
      explicitAttributeName ?? "Instrumented")
  }

  static func instrumentedFunctionBody(
    attribute: AttributeSyntax,
    functionDecl: FunctionDeclSyntax,
    explicitAttributeName: String?,
    defaultSpanName: String
  ) throws -> [CodeBlockItemSyntax] {
    guard let body = functionDecl.body else {
      throw InstrumentsMacroError.attachedMacroRequiresBody(explicitAttributeName ?? "Instrumented")
    }

    let nameExpr: ExprSyntax
    if let explicitAttributeName {
      nameExpr = try spanNameExpression(from: attribute, defaultName: defaultSpanName)
      _ = explicitAttributeName
    } else {
      nameExpr = ExprSyntax(literal: defaultSpanName)
    }

    var invocation = ""
    if functionDecl.signature.effectSpecifiers?.throwsClause != nil {
      invocation += "try "
    }
    if functionDecl.signature.effectSpecifiers?.asyncSpecifier != nil {
      invocation += "await "
    }

    return [
      "let __instrumentsRecorder = Instruments.current",
      """
      return \(raw: invocation)__instrumentsRecorder.span(\(nameExpr), attributes: .empty) \(body.trimmed)
      """,
    ]
  }

  static func instrumentedInitializerBody(
    attribute: AttributeSyntax,
    initializerDecl: InitializerDeclSyntax,
    explicitAttributeName: String?,
    defaultSpanName: String
  ) throws -> [CodeBlockItemSyntax] {
    guard let body = initializerDecl.body else {
      throw InstrumentsMacroError.attachedMacroRequiresBody(explicitAttributeName ?? "Instrumented")
    }

    let nameExpr: ExprSyntax
    if let explicitAttributeName {
      nameExpr = try spanNameExpression(from: attribute, defaultName: defaultSpanName)
      _ = explicitAttributeName
    } else {
      nameExpr = ExprSyntax(literal: defaultSpanName)
    }

    return [
      "let __instrumentsRecorder = Instruments.current",
      "let __instrumentsToken = __instrumentsRecorder.beginSpan(\(nameExpr), attributes: .empty)",
      """
      defer {
        __instrumentsRecorder.endSpan(__instrumentsToken)
      }
      """,
    ] + Array(body.statements)
  }

  static func functionName(for declaration: some DeclSyntaxProtocol) -> String? {
    declaration.as(FunctionDeclSyntax.self)?.name.text
  }

  static func initializerName(for initializerDecl: InitializerDeclSyntax) -> String {
    let labels = initializerDecl.signature.parameterClause.parameters.map { parameter in
      "\(parameter.firstName.text):"
    }.joined()
    return "init(\(labels))"
  }

  static func initializerSpanName(
    for initializerDecl: InitializerDeclSyntax,
    typeName: String
  ) -> String {
    "\(typeName).\(initializerName(for: initializerDecl))"
  }

  static func typeName(for declaration: some DeclGroupSyntax) -> String {
    if let named = declaration.asProtocol(NamedDeclSyntax.self) {
      return named.name.text
    }
    if let extensionDecl = declaration.as(ExtensionDeclSyntax.self) {
      return extensionDecl.extendedType.trimmedDescription
    }
    return "Instrumented"
  }

  static func containingTypeName(in context: some MacroExpansionContext) -> String? {
    for syntax in context.lexicalContext {
      if let structDecl = syntax.as(StructDeclSyntax.self) {
        return structDecl.name.text
      }
      if let classDecl = syntax.as(ClassDeclSyntax.self) {
        return classDecl.name.text
      }
      if let actorDecl = syntax.as(ActorDeclSyntax.self) {
        return actorDecl.name.text
      }
      if let enumDecl = syntax.as(EnumDeclSyntax.self) {
        return enumDecl.name.text
      }
      if let extensionDecl = syntax.as(ExtensionDeclSyntax.self) {
        return extensionDecl.extendedType.trimmedDescription
      }
    }

    return nil
  }

  static func hasInstrumentationAttribute(_ attributes: AttributeListSyntax) -> Bool {
    attributes.contains { element in
      guard case .attribute(let attribute) = element else {
        return false
      }
      let name = attribute.attributeName.trimmedDescription
      return name == "Span" || name == "Instrumented"
    }
  }

  static func hasInstrumentationAttribute(_ functionDecl: FunctionDeclSyntax) -> Bool {
    hasInstrumentationAttribute(functionDecl.attributes)
  }

  static func hasInstrumentationAttribute(_ initializerDecl: InitializerDeclSyntax) -> Bool {
    hasInstrumentationAttribute(initializerDecl.attributes)
  }
}
