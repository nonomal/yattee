import SwiftUI

struct CommentsView: View {
    var embedInScrollView = false
    @State private var repliesID: Comment.ID?

    @EnvironmentObject<CommentsModel> private var comments

    var body: some View {
        Group {
            if comments.disabled {
                NoCommentsView(text: "Comments are disabled".localized(), systemImage: "xmark.circle.fill")
            } else if comments.loaded && comments.all.isEmpty {
                NoCommentsView(text: "No comments".localized(), systemImage: "0.circle.fill")
            } else if !comments.loaded {
                PlaceholderProgressView()
            } else {
                let last = comments.all.last
                let commentsStack = LazyVStack {
                    ForEach(comments.all) { comment in
                        CommentView(comment: comment, repliesID: $repliesID)
                            .onAppear {
                                comments.loadNextPageIfNeeded(current: comment)
                            }
                            .borderBottom(height: comment != last ? 0.5 : 0, color: Color("ControlsBorderColor"))
                    }
                }

                if embedInScrollView {
                    ScrollView(.vertical, showsIndicators: false) {
                        commentsStack
                    }
                } else {
                    commentsStack
                }
            }
        }
        .padding(.horizontal)
    }
}

struct CommentsView_Previews: PreviewProvider {
    static var previews: some View {
        if #available(iOS 15.0, macOS 12.0, tvOS 15.0, *) {
            CommentsView()
                .previewInterfaceOrientation(.landscapeRight)
                .injectFixtureEnvironmentObjects()
        }

        CommentsView()
            .injectFixtureEnvironmentObjects()
    }
}
