import Defaults
import Foundation

enum TrendingCategory: String, CaseIterable, Identifiable, Defaults.Serializable {
    case `default`, music, gaming, movies

    var id: RawValue {
        rawValue
    }

    var title: RawValue {
        switch self {
        case .default:
            return "All".localized()
        case .music:
            return "Music".localized()
        case .gaming:
            return "Gaming".localized()
        case .movies:
            return "Movies".localized()
        }
    }

    var name: String {
        id == "default" ? "Trending".localized() : title
    }

    var controlLabel: String {
        id == "default" ? "All".localized() : title
    }
}
