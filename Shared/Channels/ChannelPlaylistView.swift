import Defaults
import Siesta
import SwiftUI

struct ChannelPlaylistView: View {
    var playlist: ChannelPlaylist?
    var showCloseButton = false

    @State private var presentingShareSheet = false
    @State private var shareURL: URL?

    @StateObject private var store = Store<ChannelPlaylist>()

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.navigationStyle) private var navigationStyle
    @Default(.channelPlaylistListingStyle) private var channelPlaylistListingStyle

    @ObservedObject private var accounts = AccountsModel.shared
    var player = PlayerModel.shared
    @ObservedObject private var recents = RecentsModel.shared

    private var items: [ContentItem] {
        ContentItem.array(of: store.item?.videos ?? [])
    }

    private var presentedPlaylist: ChannelPlaylist? {
        playlist ?? recents.presentedPlaylist
    }

    private var resource: Resource? {
        guard let playlist = presentedPlaylist else {
            return nil
        }

        let resource = accounts.api.channelPlaylist(playlist.id)
        resource?.addObserver(store)

        return resource
    }

    var body: some View {
        VStack(alignment: .leading) {
            #if os(tvOS)
                HStack {
                    if let playlist = presentedPlaylist {
                        ThumbnailView(url: store.item?.thumbnailURL ?? playlist.thumbnailURL)
                            .frame(width: 140, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 2))

                        Text(playlist.title)
                            .font(.headline)
                            .frame(alignment: .leading)
                            .lineLimit(1)

                        Spacer()

                        FavoriteButton(item: FavoriteItem(section: .channelPlaylist(accounts.app.appType.rawValue, playlist.id, playlist.title)))
                            .labelStyle(.iconOnly)
                    }

                    playButtons
                        .labelStyle(.iconOnly)
                }
            #endif
            VerticalCells(items: items)
                .environment(\.inChannelPlaylistView, true)
        }
        .environment(\.listingStyle, channelPlaylistListingStyle)
        .onAppear {
            if let playlist = presentedPlaylist,
               let cache = ChannelPlaylistsCacheModel.shared.retrievePlaylist(playlist)
            {
                store.replace(cache)
            }
            resource?.loadIfNeeded()?.onSuccess { response in
                if let playlist: ChannelPlaylist = response.typedContent() {
                    ChannelPlaylistsCacheModel.shared.storePlaylist(playlist: playlist)
                }
            }
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #endif
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                playlistMenu
            }
        }
        #endif
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if showCloseButton {
                    Button {
                        NavigationModel.shared.presentingPlaylist = false
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                    .buttonStyle(.plain)
                }
            }

            ToolbarItem(placement: playlistButtonsPlacement) {
                HStack {
                    ListingStyleButtons(listingStyle: $channelPlaylistListingStyle)
                    ShareButton(contentItem: contentItem)

                    favoriteButton

                    playButtons
                }
            }
        }
        .navigationTitle(label)
        #endif
    }

    @ViewBuilder private var favoriteButton: some View {
        if let playlist = presentedPlaylist {
            FavoriteButton(item: FavoriteItem(section: .channelPlaylist(accounts.app.appType.rawValue, playlist.id, playlist.title)))
        }
    }

    #if os(iOS)
        private var playlistMenu: some View {
            Menu {
                playButtons

                favoriteButton

                ListingStyleButtons(listingStyle: $channelPlaylistListingStyle)

                Section {
                    SettingsButtons()
                }
            } label: {
                HStack(spacing: 12) {
                    if let url = store.item?.thumbnailURL ?? playlist?.thumbnailURL {
                        ThumbnailView(url: url)
                            .frame(width: 60, height: 30)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }

                    Text(label)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .frame(maxWidth: 320)
                .transaction { t in t.animation = nil }
            }
        }
    #endif

    private var label: String {
        presentedPlaylist?.title ?? ""
    }

    private var playlistButtonsPlacement: ToolbarItemPlacement {
        #if os(iOS)
            .navigationBarTrailing
        #else
            .automatic
        #endif
    }

    private var playButtons: some View {
        Group {
            Button {
                player.play(videos)
            } label: {
                Label("Play All", systemImage: "play")
            }
            Button {
                player.play(videos, shuffling: true)
            } label: {
                Label("Shuffle All", systemImage: "shuffle")
            }
        }
    }

    private var videos: [Video] {
        items.compactMap(\.video)
    }

    private var contentItem: ContentItem {
        ContentItem(playlist: playlist)
    }
}

struct ChannelPlaylistView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ChannelPlaylistView(playlist: ChannelPlaylist.fixture)
        }
    }
}
