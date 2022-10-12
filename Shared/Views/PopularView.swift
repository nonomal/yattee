import Siesta
import SwiftUI

struct PopularView: View {
    @StateObject private var store = Store<[Video]>()

    @EnvironmentObject<AccountsModel> private var accounts

    var resource: Resource? {
        accounts.api.popular
    }

    var videos: [ContentItem] {
        ContentItem.array(of: store.collection)
    }

    var body: some View {
        BrowserPlayerControls {
            VerticalCells(items: videos)
                .onAppear {
                    resource?.addObserver(store)
                    resource?.loadIfNeeded()
                }
            #if !os(tvOS)
                .navigationTitle("Popular")
            #endif
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                FavoriteButton(item: FavoriteItem(section: .popular))
            }
        }
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                resource?.load()
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
        #if os(iOS)
        .refreshControl { refreshControl in
            resource?.load().onCompletion { _ in
                refreshControl.endRefreshing()
            }
            .onFailure { error in
                NavigationModel.shared.presentAlert(title: "Could not refresh Popular", message: error.userMessage)
            }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                resource?.load()
            }
        }
        .navigationBarTitleDisplayMode(RefreshControl.navigationBarTitleDisplayMode)
        #endif
        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            resource?.loadIfNeeded()
        }
        #endif
    }
}
