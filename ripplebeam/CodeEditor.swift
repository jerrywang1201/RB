import SwiftUI
import CodeEditorView
import LanguageSupport


private let diagsIdentifiers =
  ["DELAY", "BIF", "BINF"]

extension LanguageConfiguration {
    public static func diags(_ languageService: LanguageServiceBuilder? = nil) -> LanguageConfiguration {
        return LanguageConfiguration(name: "Diags",
                                     stringRegexp: nil,
                                     characterRegexp: nil,
                                     numberRegexp:nil,
                                     singleLineComment: "##",
                                     nestedComment: (open: "/*", close: "*/"),
                                     identifierRegexp: nil,
                                     reservedIdentifiers: diagsIdentifiers,
                                     languageService: languageService)
      }
}
