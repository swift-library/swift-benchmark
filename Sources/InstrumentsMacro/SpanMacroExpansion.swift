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

private final class NestedInstrumentsMacroLowerer: SyntaxRewriter {
  private var error: Error?

  init() {
    super.init(viewMode: .sourceAccurate)
  }

  func lower(_ closure: ClosureExprSyntax) throws -> ClosureExprSyntax {
    let rewritten = rewrite(Syntax(closure))
    if let error {
      throw error
    }
    return rewritten.as(ClosureExprSyntax.self) ?? closure
  }

  override func visit(_ node: TryExprSyntax) -> ExprSyntax {
    guard attemptLowering else {
      return ExprSyntax(node)
    }

    do {
      if let span = node.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapTry(node, around: lowerSpan(span, invocation: "try "))
      }

      if let awaitExpr = node.expression.as(AwaitExprSyntax.self),
        let span = awaitExpr.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapTry(
          node, isAwaiting: true, around: lowerSpan(span, invocation: "try await "))
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  override func visit(_ node: AwaitExprSyntax) -> ExprSyntax {
    do {
      if let span = node.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapAwait(around: lowerSpan(span, invocation: "await "))
      }

      if let tryExpr = node.expression.as(TryExprSyntax.self),
        let span = tryExpr.expression.as(MacroExpansionExprSyntax.self),
        isSpanMacro(span)
      {
        return try wrapAwait(tryExpr, around: lowerSpan(span, invocation: "try await "))
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  override func visit(_ node: MacroExpansionExprSyntax) -> ExprSyntax {
    do {
      if isSpanMacro(node) {
        return try lowerSpan(node, invocation: "")
      }

      if isEventMacro(node) {
        return try InstrumentsMacroExpansion.makeEventExpression(from: node)
      }
    } catch {
      record(error)
      return ExprSyntax(node)
    }

    return super.visit(node)
  }

  private var attemptLowering: Bool {
    error == nil
  }

  private func record(_ error: Error) {
    if self.error == nil {
      self.error = error
    }
  }

  private func isSpanMacro(_ node: MacroExpansionExprSyntax) -> Bool {
    node.macroName.text == "span"
  }

  private func isEventMacro(_ node: MacroExpansionExprSyntax) -> Bool {
    node.macroName.text == "event"
  }

  private func lowerSpan(
    _ node: MacroExpansionExprSyntax,
    invocation: String
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: invocation)
  }

  private func wrapTry(
    _ node: TryExprSyntax,
    isAwaiting: Bool = false,
    around expression: ExprSyntax
  ) -> ExprSyntax {
    let marker = node.questionOrExclamationMark?.text ?? ""
    let awaitPrefix = isAwaiting ? "await " : ""
    return "\(raw: "try\(marker) \(awaitPrefix)")\(expression)"
  }

  private func wrapAwait(
    around expression: ExprSyntax
  ) -> ExprSyntax {
    "\(raw: "await ")\(expression)"
  }

  private func wrapAwait(
    _ tryExpr: TryExprSyntax,
    around expression: ExprSyntax
  ) -> ExprSyntax {
    let marker = tryExpr.questionOrExclamationMark?.text ?? ""
    return "\(raw: "await try\(marker) ")\(expression)"
  }
}

public struct SpanMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "")
  }
}

public struct SpanThrowingMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "try ")
  }
}

public struct SpanAsyncMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "await ")
  }
}

public struct SpanAsyncThrowingMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeSpanExpression(from: node, invocation: "try await ")
  }
}

public struct EventMacro: ExpressionMacro {
  public static func expansion(
    of node: some FreestandingMacroExpansionSyntax,
    in context: some MacroExpansionContext
  ) throws -> ExprSyntax {
    try InstrumentsMacroExpansion.makeEventExpression(from: node)
  }
}

public struct SpanAttributeMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    try InstrumentsMacroExpansion.instrumentedBody(
      attribute: node,
      declaration: declaration,
      explicitAttributeName: "Span",
      defaultSpanName: InstrumentsMacroExpansion.functionName(for: declaration) ?? "span",
      context: context
    )
  }
}

public struct InstrumentedBodyMacro: BodyMacro {
  public static func expansion(
    of node: AttributeSyntax,
    providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
    in context: some MacroExpansionContext
  ) throws -> [CodeBlockItemSyntax] {
    try InstrumentsMacroExpansion.instrumentedBody(
      attribute: node,
      declaration: declaration,
      explicitAttributeName: nil,
      defaultSpanName: InstrumentsMacroExpansion.functionName(for: declaration) ?? "instrumented",
      context: context
    )
  }
}

public struct InstrumentedMembersMacro: MemberAttributeMacro {
  public static func expansion(
    of node: AttributeSyntax,
    attachedTo declaration: some DeclGroupSyntax,
    providingAttributesFor member: some DeclSyntaxProtocol,
    in context: some MacroExpansionContext
  ) throws -> [AttributeSyntax] {
    if let functionDecl = member.as(FunctionDeclSyntax.self),
      functionDecl.body != nil,
      !InstrumentsMacroExpansion.hasInstrumentationAttribute(functionDecl)
    {
      let spanName =
        "\(InstrumentsMacroExpansion.typeName(for: declaration)).\(functionDecl.name.text)"
      return ["@Span(\(literal: spanName))"]
    }

    if let initializerDecl = member.as(InitializerDeclSyntax.self),
      initializerDecl.body != nil,
      !InstrumentsMacroExpansion.hasInstrumentationAttribute(initializerDecl)
    {
      let spanName = InstrumentsMacroExpansion.initializerSpanName(
        for: initializerDecl,
        typeName: InstrumentsMacroExpansion.typeName(for: declaration)
      )
      return ["@Span(\(literal: spanName))"]
    }

    return []
  }
}
