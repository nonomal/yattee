import SwiftUI

struct QueueView: View {
    @State private var expanded = false

    @ObservedObject private var player = PlayerModel.shared

    var body: some View {
        LazyVStack {
            if !items.isEmpty {
                Button {
                    withAnimation {
                        expanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        sectionLabel(label)
                        Spacer()
                        ClearQueueButton()
                        if items.count > 1 {
                            Label("Show more", systemImage: expanded ? "chevron.up" : "chevron.down")
                                .animation(nil, value: expanded)
                                .foregroundColor(.accentColor)
                                .imageScale(.large)
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                .buttonStyle(.plain)

                LazyVStack(alignment: .leading) {
                    ForEach(limitedItems) { item in
                        ContentItemView(item: .init(video: item.video))
                            .environment(\.listingStyle, .list)
                            .environment(\.inQueueListing, true)
                            .environment(\.noListingDividers, limit == 1)
                            .transition(.opacity)
                    }
                }
            }
        }
        .padding(.vertical, items.isEmpty ? 0 : 15)
    }

    var label: String {
        if items.count < 2 {
            return "Next in Queue"
        }

        return "Next in Queue (\(items.count))"
    }

    var limitedItems: [ContentItem] {
        if let limit {
            return Array(items.prefix(limit).map(\.contentItem))
        }

        return items.map(\.contentItem)
    }

    var items: [PlayerQueueItem] {
        player.queue
    }

    var limit: Int? {
        if !expanded {
            return 1
        }

        return nil
    }

    func sectionLabel(_ label: String) -> some View {
        Text(label.localized())
            .font(.title3.bold())
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.secondary)
    }
}

struct QueueView_Previews: PreviewProvider {
    static var previews: some View {
        QueueView()
    }
}
