import AVFoundation
import Defaults
import Foundation
import Logging
import MediaPlayer
#if !os(macOS)
    import UIKit
#endif

final class AVPlayerBackend: PlayerBackend {
    static let assetKeysToLoad = ["tracks", "playable", "duration"]

    private var logger = Logger(label: "avplayer-backend")

    var model: PlayerModel! { .shared }
    var controls: PlayerControlsModel! { .shared }
    var playerTime: PlayerTimeModel! { .shared }
    var networkState: NetworkStateModel! { .shared }
    var seek: SeekModel! { .shared }

    var stream: Stream?
    var video: Video?

    var currentTime: CMTime? {
        avPlayer.currentTime()
    }

    var loadedVideo: Bool {
        !avPlayer.currentItem.isNil
    }

    var isLoadingVideo: Bool {
        model.currentItem == nil || model.time == nil || !model.time!.isValid
    }

    var isPlaying: Bool {
        avPlayer.timeControlStatus == .playing
    }

    var aspectRatio: Double {
        #if os(iOS)
            playerLayer.videoRect.width / playerLayer.videoRect.height
        #else
            VideoPlayerView.defaultAspectRatio
        #endif
    }

    var isSeeking: Bool {
        // TODO: implement this maybe?
        false
    }

    var playerItemDuration: CMTime? {
        avPlayer.currentItem?.asset.duration
    }

    private(set) var avPlayer = AVPlayer()
    private(set) var playerLayer = AVPlayerLayer()
    #if os(tvOS)
        var controller: AppleAVPlayerViewController?
    #endif
    var startPictureInPictureOnPlay = false
    var startPictureInPictureOnSwitch = false

    private var asset: AVURLAsset?
    private var composition = AVMutableComposition()
    private var loadedCompositionAssets = [AVMediaType]()

    private var frequentTimeObserver: Any?
    private var infrequentTimeObserver: Any?
    private var playerTimeControlStatusObserver: Any?

    private var statusObservation: NSKeyValueObservation?

    private var timeObserverThrottle = Throttle(interval: 2)

    internal var controlsUpdates = false

    init() {
        addFrequentTimeObserver()
        addInfrequentTimeObserver()
        addPlayerTimeControlStatusObserver()

        playerLayer.player = avPlayer
    }

    func bestPlayable(_ streams: [Stream], maxResolution: ResolutionSetting) -> Stream? {
        let sortedByResolution = streams
            .filter { ($0.kind == .adaptive || $0.kind == .stream) && $0.resolution <= maxResolution.value }
            .sorted { $0.resolution > $1.resolution }

        return streams.first { $0.kind == .hls } ??
            sortedByResolution.first { $0.kind == .stream } ??
            sortedByResolution.first
    }

    func canPlay(_ stream: Stream) -> Bool {
        stream.kind == .hls || stream.kind == .stream || (stream.kind == .adaptive && stream.format == .mp4)
    }

    func playStream(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool,
        upgrading _: Bool
    ) {
        if let url = stream.singleAssetURL {
            model.logger.info("playing stream with one asset\(stream.kind == .hls ? " (HLS)" : ""): \(url)")
            loadSingleAsset(url, stream: stream, of: video, preservingTime: preservingTime)
        } else {
            model.logger.info("playing stream with many assets:")
            model.logger.info("composition audio asset: \(stream.audioAsset.url)")
            model.logger.info("composition video asset: \(stream.videoAsset.url)")

            loadComposition(stream, of: video, preservingTime: preservingTime)
        }
    }

    func play() {
        guard avPlayer.timeControlStatus != .playing else {
            return
        }

        avPlayer.play()
        model.objectWillChange.send()
    }

    func pause() {
        guard avPlayer.timeControlStatus != .paused else {
            return
        }

        avPlayer.pause()
        model.objectWillChange.send()
    }

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func stop() {
        avPlayer.replaceCurrentItem(with: nil)
    }

    func seek(to time: CMTime, seekType _: SeekType, completionHandler: ((Bool) -> Void)?) {
        guard !model.live else { return }

        avPlayer.seek(
            to: time,
            toleranceBefore: .zero,
            toleranceAfter: .zero,
            completionHandler: completionHandler ?? { _ in }
        )
    }

    func setRate(_ rate: Float) {
        avPlayer.rate = rate
    }

    func closeItem() {
        avPlayer.replaceCurrentItem(with: nil)
        video = nil
        stream = nil
    }

    func closePiP() {
        model.pipController?.stopPictureInPicture()
    }

    private func loadSingleAsset(
        _ url: URL,
        stream: Stream,
        of video: Video,
        preservingTime: Bool = false
    ) {
        asset?.cancelLoading()
        asset = AVURLAsset(url: url)
        asset?.loadValuesAsynchronously(forKeys: Self.assetKeysToLoad) { [weak self] in
            var error: NSError?
            switch self?.asset?.statusOfValue(forKey: "duration", error: &error) {
            case .loaded:
                DispatchQueue.main.async { [weak self] in
                    self?.insertPlayerItem(stream, for: video, preservingTime: preservingTime)
                }
            case .failed:
                DispatchQueue.main.async { [weak self] in
                    self?.model.playerError = error
                }
            default:
                return
            }
        }
    }

    private func loadComposition(
        _ stream: Stream,
        of video: Video,
        preservingTime: Bool = false
    ) {
        loadedCompositionAssets = []
        loadCompositionAsset(stream.audioAsset, stream: stream, type: .audio, of: video, preservingTime: preservingTime, model: model)
        loadCompositionAsset(stream.videoAsset, stream: stream, type: .video, of: video, preservingTime: preservingTime, model: model)
    }

    private func loadCompositionAsset(
        _ asset: AVURLAsset,
        stream: Stream,
        type: AVMediaType,
        of video: Video,
        preservingTime: Bool = false,
        model: PlayerModel
    ) {
        asset.loadValuesAsynchronously(forKeys: Self.assetKeysToLoad) { [weak self] in
            guard let self else {
                return
            }
            model.logger.info("loading \(type.rawValue) track")

            let assetTracks = asset.tracks(withMediaType: type)

            guard let compositionTrack = self.composition.addMutableTrack(
                withMediaType: type,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                model.logger.critical("composition \(type.rawValue) addMutableTrack FAILED")
                return
            }

            guard let assetTrack = assetTracks.first else {
                model.logger.critical("asset \(type.rawValue) track FAILED")
                return
            }

            try! compositionTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: CMTime.secondsInDefaultTimescale(video.length)),
                of: assetTrack,
                at: .zero
            )

            model.logger.critical("\(type.rawValue) LOADED")

            guard model.streamSelection == stream else {
                model.logger.critical("IGNORING LOADED")
                return
            }

            self.loadedCompositionAssets.append(type)

            if self.loadedCompositionAssets.count == 2 {
                self.insertPlayerItem(stream, for: video, preservingTime: preservingTime)
            }
        }
    }

    private func insertPlayerItem(
        _ stream: Stream,
        for video: Video,
        preservingTime: Bool = false
    ) {
        removeItemDidPlayToEndTimeObserver()

        model.playerItem = playerItem(stream)
        guard model.playerItem != nil else {
            return
        }

        addItemDidPlayToEndTimeObserver()
        attachMetadata()

        DispatchQueue.main.async {
            self.stream = stream
            self.video = video
            self.model.stream = stream
            self.composition = AVMutableComposition()
            self.asset = nil
        }

        let startPlaying = {
            #if !os(macOS)
                try? AVAudioSession.sharedInstance().setActive(true)
            #endif

            self.setRate(self.model.currentRate)

            guard let item = self.model.playerItem, self.isAutoplaying(item) else { return }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self else {
                    return
                }

                if !preservingTime,
                   !self.model.transitioningToPiP,
                   let segment = self.model.sponsorBlock.segments.first,
                   segment.start < 3,
                   self.model.lastSkipped.isNil
                {
                    self.avPlayer.seek(
                        to: segment.endTime,
                        toleranceBefore: .secondsInDefaultTimescale(1),
                        toleranceAfter: .zero
                    ) { finished in
                        guard finished else {
                            return
                        }

                        self.model.lastSkipped = segment
                        self.model.play()
                    }
                } else {
                    self.model.play()
                }
            }
        }

        let replaceItemAndSeek = {
            guard video == self.model.currentVideo else {
                return
            }
            self.avPlayer.replaceCurrentItem(with: self.model.playerItem)
            self.seekToPreservedTime { finished in
                guard finished else {
                    return
                }

                DispatchQueue.main.async { [weak self] in
                    self?.model.preservedTime = nil
                }

                startPlaying()
            }
        }

        if preservingTime {
            if model.preservedTime.isNil {
                model.saveTime {
                    replaceItemAndSeek()
                    startPlaying()
                }
            } else {
                replaceItemAndSeek()
                startPlaying()
            }
        } else {
            avPlayer.replaceCurrentItem(with: model.playerItem)
            startPlaying()
        }
    }

    private func seekToPreservedTime(completionHandler: @escaping (Bool) -> Void = { _ in }) {
        guard let time = model.preservedTime else {
            return
        }

        avPlayer.seek(
            to: time,
            toleranceBefore: .secondsInDefaultTimescale(1),
            toleranceAfter: .zero,
            completionHandler: completionHandler
        )
    }

    private func playerItem(_: Stream) -> AVPlayerItem? {
        if let asset {
            return AVPlayerItem(asset: asset)
        } else {
            return AVPlayerItem(asset: composition)
        }
    }

    private func attachMetadata() {
        guard let video = model.currentVideo else { return }

        #if !os(macOS)
            var externalMetadata = [
                makeMetadataItem(.commonIdentifierTitle, value: video.title),
                makeMetadataItem(.quickTimeMetadataGenre, value: video.genre ?? ""),
                makeMetadataItem(.commonIdentifierDescription, value: video.description ?? "")
            ]

            if let thumbnailURL = video.thumbnailURL(quality: .medium) {
                let task = URLSession.shared.dataTask(with: thumbnailURL) { [weak self] thumbnailData, _, _ in
                    guard let thumbnailData else { return }

                    let image = UIImage(data: thumbnailData)
                    if let pngData = image?.pngData() {
                        if let artworkItem = self?.makeMetadataItem(.commonIdentifierArtwork, value: pngData) {
                            externalMetadata.append(artworkItem)
                        }
                    }

                    self?.avPlayer.currentItem?.externalMetadata = externalMetadata
                }

                task.resume()
            }

        #endif

        if let item = model.playerItem {
            #if !os(macOS)
                item.externalMetadata = externalMetadata
            #endif
            item.preferredForwardBufferDuration = 5
            observePlayerItemStatus(item)
        }
    }

    #if !os(macOS)
        private func makeMetadataItem(_ identifier: AVMetadataIdentifier, value: Any) -> AVMetadataItem {
            let item = AVMutableMetadataItem()

            item.identifier = identifier
            item.value = value as? NSCopying & NSObjectProtocol
            item.extendedLanguageTag = "und"

            return item.copy() as! AVMetadataItem
        }
    #endif

    func isAutoplaying(_ item: AVPlayerItem) -> Bool {
        avPlayer.currentItem == item
    }

    private func observePlayerItemStatus(_ item: AVPlayerItem) {
        statusObservation?.invalidate()
        statusObservation = item.observe(\.status, options: [.old, .new]) { [weak self] playerItem, _ in
            guard let self else {
                return
            }

            switch playerItem.status {
            case .readyToPlay:
                if self.model.playingInPictureInPicture {
                    self.startPictureInPictureOnSwitch = false
                    self.startPictureInPictureOnPlay = false
                }
                if self.model.activeBackend == .appleAVPlayer,
                   self.isAutoplaying(playerItem)
                {
                    self.model.updateAspectRatio()

                    if self.startPictureInPictureOnPlay,
                       let controller = self.model.pipController,
                       controller.isPictureInPicturePossible
                    {
                        self.tryStartingPictureInPicture()
                    } else {
                        self.model.play()
                    }
                } else if self.startPictureInPictureOnPlay {
                    self.startPictureInPictureOnPlay = false
                    self.model.stream = self.stream
                    self.model.streamSelection = self.stream

                    if self.model.activeBackend != .appleAVPlayer {
                        self.startPictureInPictureOnSwitch = true
                        let seconds = self.model.mpvBackend.currentTime?.seconds ?? 0
                        self.seek(to: seconds, seekType: .backendSync) { _ in
                            DispatchQueue.main.async {
                                self.model.pause()
                                self.model.changeActiveBackend(from: .mpv, to: .appleAVPlayer, changingStream: false)
                            }
                        }
                    }
                }
            case .failed:
                DispatchQueue.main.async {
                    self.model.playerError = item.error
                }

            default:
                return
            }
        }
    }

    private func addItemDidPlayToEndTimeObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(itemDidPlayToEndTime),
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: model.playerItem
        )
    }

    private func removeItemDidPlayToEndTimeObserver() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSNotification.Name.AVPlayerItemDidPlayToEndTime,
            object: model.playerItem
        )
    }

    @objc func itemDidPlayToEndTime() {
        if Defaults[.closeLastItemOnPlaybackEnd] {
            model.prepareCurrentItemForHistory(finished: true)
        }

        eofPlaybackModeAction()
    }

    private func addFrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(0.5)

        frequentTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self, self.model.activeBackend == .appleAVPlayer else {
                return
            }

            guard !self.model.currentItem.isNil else {
                return
            }

            self.model.updateNowPlayingInfo()

            #if os(macOS)
                MPNowPlayingInfoCenter.default().playbackState = self.avPlayer.timeControlStatus == .playing ? .playing : .paused
            #endif

            if self.controls.isPlaying != self.isPlaying {
                DispatchQueue.main.async {
                    self.controls.isPlaying = self.isPlaying
                }
            }

            if let currentTime = self.currentTime {
                self.model.handleSegments(at: currentTime)
            }

            #if !os(macOS)
                guard UIApplication.shared.applicationState != .background else {
                    print("not performing controls updates in background")
                    return
                }
            #endif

            if self.controlsUpdates {
                self.updateControls()
            }
        }
    }

    private func addInfrequentTimeObserver() {
        let interval = CMTime.secondsInDefaultTimescale(5)

        infrequentTimeObserver = avPlayer.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            guard let self else {
                return
            }

            guard !self.model.currentItem.isNil else {
                return
            }

            self.timeObserverThrottle.execute {
                self.model.updateWatch()
            }
        }
    }

    private func addPlayerTimeControlStatusObserver() {
        playerTimeControlStatusObserver = avPlayer.observe(\.timeControlStatus) { [weak self] player, _ in
            guard let self,
                  self.avPlayer == player,
                  self.model.activeBackend == .appleAVPlayer
            else {
                return
            }

            let isPlaying = player.timeControlStatus == .playing

            if self.controls.isPlaying != isPlaying {
                DispatchQueue.main.async {
                    self.controls.isPlaying = player.timeControlStatus == .playing
                }
            }

            if player.timeControlStatus != .waitingToPlayAtSpecifiedRate {
                DispatchQueue.main.async { [weak self] in
                    self?.model.objectWillChange.send()
                }
            }

            if player.timeControlStatus == .playing {
                self.model.objectWillChange.send()
                if player.rate != self.model.currentRate {
                    player.rate = self.model.currentRate
                }
            }

            #if os(macOS)
                if player.timeControlStatus == .playing {
                    ScreenSaverManager.shared.disable(reason: "Yattee is playing video")
                } else {
                    ScreenSaverManager.shared.enable()
                }
            #endif

            self.timeObserverThrottle.execute {
                self.model.updateWatch()
            }
        }
    }

    func startControlsUpdates() {
        guard model.presentingPlayer, model.controls.presentingControls, !model.controls.presentingOverlays else {
            logger.info("ignored controls update start")
            return
        }
        logger.info("starting controls updates")
        controlsUpdates = true
        model.objectWillChange.send()
    }

    func stopControlsUpdates() {
        controlsUpdates = false
        model.objectWillChange.send()
    }

    func startMusicMode() {
        if model.playingInPictureInPicture {
            closePiP()
        }

        playerLayer.player = nil

        toggleVisualTracksEnabled(false)
    }

    func stopMusicMode() {
        playerLayer.player = avPlayer

        toggleVisualTracksEnabled(true)
    }

    func toggleVisualTracksEnabled(_ value: Bool) {
        if let item = avPlayer.currentItem {
            for playerItemTrack in item.tracks {
                if let assetTrack = playerItemTrack.assetTrack,
                   assetTrack.hasMediaCharacteristic(AVMediaCharacteristic.visual)
                {
                    playerItemTrack.isEnabled = value
                }
            }
        }
    }

    func didChangeTo() {
        if startPictureInPictureOnSwitch {
            startPictureInPictureOnSwitch = false
            tryStartingPictureInPicture()
        } else if model.musicMode {
            startMusicMode()
        } else {
            stopMusicMode()
        }
    }

    func tryStartingPictureInPicture() {
        guard let controller = model.pipController else { return }

        var opened = false
        for delay in [0.1, 0.3, 0.5, 1, 2, 3, 5] {
            Delay.by(delay) {
                guard !opened else { return }
                if controller.isPictureInPicturePossible {
                    opened = true
                    controller.startPictureInPicture()
                } else {
                    print("PiP not possible, waited \(delay) seconds")
                }
            }
        }
    }

    func getTimeUpdates() {}
    func setNeedsDrawing(_: Bool) {}
    func setSize(_: Double, _: Double) {}
    func setNeedsNetworkStateUpdates(_: Bool) {}
}
