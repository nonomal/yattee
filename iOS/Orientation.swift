import CoreMotion
import Defaults
import Logging
import UIKit

struct Orientation {
    static var logger = Logger(label: "stream.yattee.orientation")

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask) {
        if let delegate = AppDelegate.instance {
            delegate.orientationLock = orientation

            let orientationString = orientation == .portrait ? "portrait" : orientation == .landscapeLeft ? "landscapeLeft" :
                orientation == .landscapeRight ? "landscapeRight" : orientation == .portraitUpsideDown ? "portraitUpsideDown" :
                orientation == .landscape ? "landscape" : orientation == .all ? "all" : "allButUpsideDown"

            logger.info("locking \(orientationString)")
        }
    }

    static func lockOrientation(_ orientation: UIInterfaceOrientationMask, andRotateTo rotateOrientation: UIInterfaceOrientation? = nil) {
        lockOrientation(orientation)

        guard let rotateOrientation else {
            return
        }

        let orientationString = rotateOrientation == .portrait ? "portrait" : rotateOrientation == .landscapeLeft ? "landscapeLeft" :
            rotateOrientation == .landscapeRight ? "landscapeRight" : rotateOrientation == .portraitUpsideDown ? "portraitUpsideDown" : "allButUpsideDown"

        logger.info("rotating to \(orientationString)")

        UIDevice.current.setValue(rotateOrientation.rawValue, forKey: "orientation")
        UINavigationController.attemptRotationToDeviceOrientation()

        if #available(iOS 16, *) {
            guard let windowScene = SafeArea.scene else { return }
            let rotateOrientationMask = rotateOrientation == .portrait ? UIInterfaceOrientationMask.portrait :
                rotateOrientation == .landscapeLeft ? .landscapeLeft :
                rotateOrientation == .landscapeRight ? .landscapeRight :
                .allButUpsideDown

            windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: rotateOrientationMask)) { error in
                print("denied rotation \(error)")
            }
        }
    }
}
