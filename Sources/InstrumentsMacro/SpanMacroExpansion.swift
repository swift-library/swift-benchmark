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
      return "@\(attribute) can only instrument functions with bodies."
    case .attachedMacroRequiresBody(let attribute):
      return "@\(attribute) requires a function body to instrument."
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

    return """
      {
        let __instrumentsRecorder = Instruments.current
        let __instrumentsToken = __instrumentsRecorder.beginSpan(\(parsed.nameExpr), attributes: \(parsed.attributesExpr))
        defer {
          __instrumentsRecorder.endSpan(__instrumentsToken)
        }
        return \(raw: invocation)\(closure)()
      }()
      """
  }

  static func makeEventExpression(
    from node: some FreestandingMacroExpansionSyntax
  ) throws -> ExprSyntax {
    let parsed = try parseEventArguments(from: Array(node.arguments))
    return "Instruments.current.recordEvent(\(parsed.nameExpr), attributes: \(parsed.attributesExpr))"
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
    defaultSpanName: String
  ) throws -> [CodeBlockItemSyntax] {
    guard declaration.as(FunctionDeclSyntax.self) != nil else {
      throw InstrumentsMacroError.unsupportedAttachedDeclaration(explicitAttributeName ?? "Instrumented")
    }
    guard let body = declaration.body else {
      throw InstrumentsMacroError.attachedMacroRequiresBody(explicitAttributeName ?? "Instrumented")
    }
    guard let functionDecl = declaration.as(FunctionDeclSyntax.self) else {
      throw InstrumentsMacroError.unsupportedAttachedDeclaration(explicitAttributeName ?? "Instrumented")
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

  static func functionName(for declaration: some DeclSyntaxProtocol) -> String? {
    declaration.as(FunctionDeclSyntax.self)?.name.text
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

  static func hasInstrumentationAttribute(_ functionDecl: FunctionDeclSyntax) -> Bool {
    functionDecl.attributes.contains { element in
      guard case .attribute(let attribute) = element else {
        return false
      }
      let name = attribute.attributeName.trimmedDescription
      return name == "Span" || name == "Instrumented"
    }
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
      defaultSpanName: InstrumentsMacroExpansion.functionName(for: declaration) ?? "span"
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
      defaultSpanName: InstrumentsMacroExpansion.functionName(for: declaration) ?? "instrumented"
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
    guard let functionDecl = member.as(FunctionDeclSyntax.self),
      functionDecl.body != nil,
      !InstrumentsMacroExpansion.hasInstrumentationAttribute(functionDecl)
    else {
      return []
    }

    let spanName = "\(InstrumentsMacroExpansion.typeName(for: declaration)).\(functionDecl.name.text)"
    return ["@Span(\(literal: spanName))"]
  }
}
