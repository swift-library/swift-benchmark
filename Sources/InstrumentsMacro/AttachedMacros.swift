// SPDX-License-Identifier: Apache-2.0 WITH Swift-exception
// Copyright (c) 2020-present Xudong Xu

import SwiftSyntax
import SwiftSyntaxMacros

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
