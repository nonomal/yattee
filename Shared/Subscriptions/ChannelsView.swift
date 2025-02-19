import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct ChannelsView: View {
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var feedCount = UnwatchedFeedCountModel.shared

    @Default(.showCacheStatus) private var showCacheStatus

    var body: some View {
        List {
            Section(header: header) {
                ForEach(subscriptions.all) { channel in
                    NavigationLink(destination: ChannelVideosView(channel: channel)) {
                        HStack {
                            if let url = channel.thumbnailURLOrCached {
                                ThumbnailView(url: url)
                                    .frame(width: 35, height: 35)
                                    .clipShape(RoundedRectangle(cornerRadius: 35))
                                Text(channel.name)
                            } else {
                                Label(channel.name, systemImage: RecentsModel.symbolSystemImage(channel.name))
                            }
                        }
                        .backport
                        .badge(feedCount.unwatchedByChannelText(channel))
                    }
                    .contextMenu {
                        if subscriptions.isSubscribing(channel.id) {
                            toggleWatchedButton(channel)
                        }
                        Button {
                            subscriptions.unsubscribe(channel.id)
                        } label: {
                            Label("Unsubscribe", systemImage: "xmark.circle")
                        }
                    }
                }
                #if os(tvOS)
                .padding(.horizontal, 50)
                #endif

                Color.clear.padding(.bottom, 50)
                    .listRowBackground(Color.clear)
                    .backport
                    .listRowSeparator(false)
            }
        }
        .onAppear {
            subscriptions.load()
        }
        .onChange(of: accounts.current) { _ in
            subscriptions.load(force: true)
        }
        #if os(iOS)
        .refreshControl { refreshControl in
            subscriptions.load(force: true) {
                refreshControl.endRefreshing()
            }
        }
        .backport
        .refreshable {
            await subscriptions.load(force: true)
        }
        #endif
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                subscriptions.load(force: true)
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            subscriptions.load()
        }
        #endif
        #if os(tvOS)
        .padding(.horizontal, 30)
        #endif
    }

    var header: some View {
        HStack {
            #if os(tvOS)
                SubscriptionsPageButton()
            #endif

            if showCacheStatus {
                Spacer()

                CacheStatusHeader(
                    refreshTime: subscriptions.formattedCacheTime,
                    isLoading: subscriptions.isLoading
                )
            }

            #if os(tvOS)
                if !showCacheStatus {
                    Spacer()
                }
                Button {
                    subscriptions.load(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .imageScale(.small)
                        .font(.caption2)
                }

            #endif
        }
        #if os(tvOS)
        .padding(.bottom, 15)
        .padding(.top, 15)
        #endif
    }

    @ViewBuilder func toggleWatchedButton(_ channel: Channel) -> some View {
        if feed.canMarkChannelAsWatched(channel.id) {
            markChannelAsWatchedButton(channel)
        } else {
            markChannelAsUnwatchedButton(channel)
        }
    }

    func markChannelAsWatchedButton(_ channel: Channel) -> some View {
        Button {
            feed.markChannelAsWatched(channel.id)
        } label: {
            Label("Mark channel feed as watched", systemImage: "checkmark.circle.fill")
        }
        .disabled(!feed.canMarkAllFeedAsWatched)
    }

    func markChannelAsUnwatchedButton(_ channel: Channel) -> some View {
        Button {
            feed.markChannelAsUnwatched(channel.id)
        } label: {
            Label("Mark channel feed as unwatched", systemImage: "checkmark.circle")
        }
    }
}

struct ChannelsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            ChannelsView()
        }
    }
}
