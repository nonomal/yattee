import AVKit
import Defaults
import Foundation
import SwiftUI

final class PiPDelegate: NSObject, AVPictureInPictureControllerDelegate {
    var player: PlayerModel!

    func pictureInPictureController(
        _: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        print(error.localizedDescription)
    }

    func pictureInPictureControllerWillStartPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureControllerDidStartPictureInPicture(_: AVPictureInPictureController) {
        guard let player else { return }

        player.playingInPictureInPicture = true
        player.avPlayerBackend.startPictureInPictureOnPlay = false
        player.avPlayerBackend.startPictureInPictureOnSwitch = false
        player.controls.objectWillChange.send()

        if Defaults[.closePlayerOnOpeningPiP] { Delay.by(0.1) { player.hide() } }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_: AVPictureInPictureController) {
        guard let player else { return }

        player.playingInPictureInPicture = false
        player.controls.objectWillChange.send()
    }

    func pictureInPictureControllerWillStopPictureInPicture(_: AVPictureInPictureController) {}

    func pictureInPictureController(
        _: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        var delay = 0.0
        #if os(iOS)
            if !player.presentingPlayer {
                delay = 0.5
            }
            if player.currentItem.isNil {
                delay = 1
            }
        #endif

        if !player.currentItem.isNil, !player.musicMode {
            player?.show()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            withAnimation(.linear(duration: 0.3)) {
                self?.player.playingInPictureInPicture = false
            }

            completionHandler(true)
        }
    }
}
