import Defaults
import Siesta
import SwiftUI

struct FeedView: View {
    @ObservedObject private var feed = FeedModel.shared
    @ObservedObject private var accounts = AccountsModel.shared

    @Default(.showCacheStatus) private var showCacheStatus

    #if os(tvOS)
        @Default(.subscriptionsListingStyle) private var subscriptionsListingStyle
    #endif

    var videos: [ContentItem] {
        ContentItem.array(of: feed.videos)
    }

    var body: some View {
        VerticalCells(items: videos) { if shouldDisplayHeader { header } }
            .environment(\.loadMoreContentHandler) { feed.loadNextPage() }
            .onAppear {
                feed.loadResources()
            }
        #if os(iOS)
            .refreshControl { refreshControl in
                feed.loadResources(force: true) {
                    refreshControl.endRefreshing()
                }
            }
            .backport
            .refreshable {
                await feed.loadResources(force: true)
            }
        #endif
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                feed.loadResources(force: true)
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            feed.loadResources()
        }
        #endif
    }

    var header: some View {
        HStack {
            #if os(tvOS)
                SubscriptionsPageButton()
                ListingStyleButtons(listingStyle: $subscriptionsListingStyle)
            #endif

            if showCacheStatus {
                Spacer()

                CacheStatusHeader(
                    refreshTime: feed.formattedFeedTime,
                    isLoading: feed.isLoading
                )
            }

            #if os(tvOS)
                if !showCacheStatus {
                    Spacer()
                }
                Button {
                    feed.loadResources(force: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .imageScale(.small)
                        .font(.caption2)
                }
            #endif
        }
        .padding(.leading, 30)
        #if os(tvOS)
            .padding(.bottom, 15)
        #endif
    }

    var shouldDisplayHeader: Bool {
        #if os(tvOS)
            true
        #else
            showCacheStatus
        #endif
    }
}

struct SubscriptonsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            FeedView()
        }
    }
}
