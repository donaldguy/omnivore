import Models
import SwiftUI
import Utils

public struct FeedCard: View {
  @ObservedObject var item: LinkedItem

  public init(item: LinkedItem) {
    self.item = item
  }

  public var body: some View {
    VStack {
      HStack(alignment: .top, spacing: 6) {
        VStack(alignment: .leading, spacing: 6) {
          Text(item.unwrappedTitle)
            .font(.appSubheadline)
            .foregroundColor(.appGrayTextContrast)
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)

          if let author = item.author {
            Text("By \(author)")
              .font(.appCaption)
              .foregroundColor(.appGrayText)
              .lineLimit(1)
          }

          if let publisherURL = item.publisherHostname {
            Text(publisherURL)
              .font(.appCaption)
              .foregroundColor(.appGrayText)
              .underline()
              .lineLimit(1)
          }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.leading)
        .padding(0)

        Group {
          if let imageURL = item.imageURL {
            AsyncLoadingImage(url: imageURL) { imageStatus in
              if case let AsyncImageStatus.loaded(image) = imageStatus {
                image
                  .resizable()
                  .aspectRatio(1, contentMode: .fill)
                  .frame(width: 80, height: 80)
                  .cornerRadius(6)
              } else if case AsyncImageStatus.loading = imageStatus {
                Color.appButtonBackground
                  .frame(width: 80, height: 80)
                  .cornerRadius(6)
              } else {
                EmptyView()
              }
            }
          }
        }
      }

      // Category Labels
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(item.labels.asArray(of: LinkedItemLabel.self), id: \.self) {
            TextChip(feedItemLabel: $0)
          }
          Spacer()
        }
      }
      .padding(.bottom, 5)
    }
    .padding(.top, 5)
  }
}
