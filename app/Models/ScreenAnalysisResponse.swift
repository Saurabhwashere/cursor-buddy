import Foundation

struct ScreenAnalysisResponse: Codable, Equatable {
    let answer: String
    let steps: [String]
    let points: [PointerPoint]
    let riskWarnings: [String]
    let checklist: Checklist?

    static let empty = ScreenAnalysisResponse(
        answer: "",
        steps: [],
        points: [],
        riskWarnings: [],
        checklist: nil
    )

    init(
        answer: String,
        steps: [String],
        points: [PointerPoint],
        riskWarnings: [String],
        checklist: Checklist? = nil
    ) {
        self.answer = answer
        self.steps = steps
        self.points = points
        self.riskWarnings = riskWarnings
        self.checklist = checklist
    }
}

struct Checklist: Codable, Equatable {
    let title: String
    let items: [String]
}

enum GuidanceMode: String, CaseIterable, Identifiable {
    case nextStep
    case plainEnglish
    case checklist
    case riskCheck

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nextStep:
            return "Next Step"
        case .plainEnglish:
            return "Explain"
        case .checklist:
            return "Checklist"
        case .riskCheck:
            return "Risk Check"
        }
    }

    var modeInstruction: String {
        switch self {
        case .nextStep:
            return "Focus on one immediate practical action. Include one pointer if a visible target matters."
        case .plainEnglish:
            return "Explain what the screen is for in plain English. Keep steps minimal and only include a pointer if it clarifies the explanation."
        case .checklist:
            return "Create a reusable checklist for this task. Fill the checklist field with a short title and 3-7 items. Keep answer brief."
        case .riskCheck:
            return "Focus on risks, trust signals, official URLs, sensitive data, irreversible actions, and what the user should verify before continuing."
        }
    }
}

struct PointerPoint: Codable, Identifiable, Equatable {
    let id: UUID
    let x: Double
    let y: Double
    let label: String

    init(id: UUID = UUID(), x: Double, y: Double, label: String) {
        self.id = id
        self.x = x
        self.y = y
        self.label = label
    }

    enum CodingKeys: String, CodingKey {
        case x
        case y
        case label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        x = try container.decode(Double.self, forKey: .x)
        y = try container.decode(Double.self, forKey: .y)
        label = try container.decode(String.self, forKey: .label)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(label, forKey: .label)
    }
}

struct CapturedScreenshot: Equatable {
    let fileURL: URL
    let pngData: Data
    let width: Int
    let height: Int
    let scale: Double
}
