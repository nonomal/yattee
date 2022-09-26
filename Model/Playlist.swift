import Foundation
import SwiftyJSON

struct Playlist: Identifiable, Equatable, Hashable {
    enum Visibility: String, CaseIterable, Identifiable {
        case `public`, unlisted, `private`

        var id: String {
            rawValue
        }

        var name: String {
            rawValue.capitalized.localized()
        }
    }

    let id: String
    var title: String
    var visibility: Visibility
    var editable = true

    var updated: TimeInterval?

    var videos = [Video]()

    init(id: String, title: String, visibility: Visibility, editable: Bool = true, updated: TimeInterval? = nil, videos: [Video] = []) {
        self.id = id
        self.title = title
        self.visibility = visibility
        self.editable = editable
        self.updated = updated
        self.videos = videos
    }

    init(_ json: JSON) {
        id = json["playlistId"].stringValue
        title = json["title"].stringValue
        visibility = json["isListed"].boolValue ? .public : .private
        updated = json["updated"].doubleValue
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id && lhs.updated == rhs.updated
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
