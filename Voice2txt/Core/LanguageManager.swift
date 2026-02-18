import Foundation

struct Language {
    let code: String
    let name: String
}

class LanguageManager {
    static let shared = LanguageManager()

    private let defaultsKey = "com.writeon.app.language"

    let availableLanguages: [Language] = [
        Language(code: "en", name: "English"),
        Language(code: "es", name: "Spanish"),
        Language(code: "fr", name: "French"),
        Language(code: "de", name: "German"),
        Language(code: "pt", name: "Portuguese"),
        Language(code: "it", name: "Italian"),
        Language(code: "nl", name: "Dutch"),
        Language(code: "ja", name: "Japanese"),
        Language(code: "zh", name: "Chinese"),
        Language(code: "ko", name: "Korean"),
        Language(code: "ru", name: "Russian"),
        Language(code: "hi", name: "Hindi"),
        Language(code: "ar", name: "Arabic"),
        Language(code: "sv", name: "Swedish"),
        Language(code: "pl", name: "Polish"),
        Language(code: "tr", name: "Turkish"),
        Language(code: "uk", name: "Ukrainian"),
        Language(code: "da", name: "Danish"),
        Language(code: "no", name: "Norwegian"),
        Language(code: "fi", name: "Finnish"),
    ]

    var currentLanguage: String {
        get { UserDefaults.standard.string(forKey: defaultsKey) ?? "en" }
        set { UserDefaults.standard.set(newValue, forKey: defaultsKey) }
    }

    var currentLanguageName: String {
        availableLanguages.first { $0.code == currentLanguage }?.name ?? "English"
    }

    private init() {}
}
