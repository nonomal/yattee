import Defaults
import Foundation

struct InstancesBridge: Defaults.Bridge {
    typealias Value = Instance
    typealias Serializable = [String: String]

    func serialize(_ value: Value?) -> Serializable? {
        guard let value else {
            return nil
        }

        return [
            "app": value.app.rawValue,
            "id": value.id,
            "name": value.name,
            "apiURL": value.apiURL,
            "frontendURL": value.frontendURL ?? "",
            "proxiesVideos": value.proxiesVideos ? "true" : "false"
        ]
    }

    func deserialize(_ object: Serializable?) -> Value? {
        guard
            let object,
            let app = VideosApp(rawValue: object["app"] ?? ""),
            let id = object["id"],
            let apiURL = object["apiURL"]
        else {
            return nil
        }

        let name = object["name"] ?? ""
        let frontendURL: String? = object["frontendURL"]!.isEmpty ? nil : object["frontendURL"]
        let proxiesVideos = object["proxiesVideos"] == "true"

        return Instance(app: app, id: id, name: name, apiURL: apiURL, frontendURL: frontendURL, proxiesVideos: proxiesVideos)
    }
}
