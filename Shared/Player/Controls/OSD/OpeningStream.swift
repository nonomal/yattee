import SwiftUI

struct OpeningStream: View {
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<NetworkStateModel> private var model

    var body: some View {
        Buffering(reason: reason, state: state)
            .opacity(visible ? 1 : 0)
    }

    var visible: Bool {
        (!player.currentItem.isNil && !player.videoBeingOpened.isNil) || (player.isLoadingVideo && !model.pausedForCache && !player.isSeeking)
    }

    var reason: String {
        guard player.videoBeingOpened != nil else {
            return "Loading streams...".localized()
        }

        if player.musicMode {
            return "Opening audio stream...".localized()
        }

        return String(format: "Opening %@ stream...".localized(), streamQuality)
    }

    var state: String? {
        player.videoBeingOpened.isNil ? model.bufferingStateText : nil
    }

    var streamQuality: String {
        guard let stream = player.streamSelection else { return " " }
        guard !player.musicMode else { return " audio " }

        return " \(stream.shortQuality) "
    }
}

struct OpeningStream_Previews: PreviewProvider {
    static var previews: some View {
        OpeningStream()
            .injectFixtureEnvironmentObjects()
    }
}
