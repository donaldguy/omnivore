import Foundation
import Models
import Services
import SwiftUI
import Transmission
import Utils
import Views

@MainActor
struct LibraryTabView: View {
  @EnvironmentObject var dataService: DataService
  @EnvironmentObject var audioController: AudioController

  @AppStorage("LibraryTabView::hideFollowingTab") var hideFollowingTab = false
  @AppStorage(UserDefaultKey.lastSelectedTabItem.rawValue) var selectedTab = "inbox"

  @State var isEditMode: EditMode = .inactive
  @State var showExpandedAudioPlayer = false
  @State var presentPushContainer = true
  @State var pushLinkRequest: String?

  private let syncManager = LibrarySyncManager()

  @MainActor
  public init() {
    UITabBar.appearance().isHidden = true
  }

  @StateObject private var inboxViewModel = HomeFeedViewModel(
    filterKey: "lastSelectedFilter-inbox",
    fetcher: LibraryItemFetcher(),
    folderConfigs: [
      "inbox": LibraryListConfig(
        hasFeatureCards: true,
        hasReadNowSection: true,
        leadingSwipeActions: [.pin],
        trailingSwipeActions: [.archive, .delete],
        cardStyle: .library
      )
    ]
  )

  @StateObject private var followingViewModel = HomeFeedViewModel(
    filterKey: "lastSelectedFilter-following",
    fetcher: LibraryItemFetcher(),
    folderConfigs: [
      "following": LibraryListConfig(
        hasFeatureCards: false,
        hasReadNowSection: false,
        leadingSwipeActions: [.moveToInbox],
        trailingSwipeActions: [.delete],
        cardStyle: .library
      )
    ]
  )

  var currentViewModel: HomeFeedViewModel? {
    switch selectedTab {
    case "inbox":
      return inboxViewModel
    case "following":
      return followingViewModel
    default:
      return nil
    }
  }

  @State var showOperationToast = false
  @State var operationStatus: OperationStatus = .none
  @State var operationMessage: String?

  @State var digestEnabled = false

  var showDigest: Bool {
    if digestEnabled, #available(iOS 17.0, *) {
      return true
    }
    return false
  }

  var displayTabs: [String] {
    var res = [String]()
    if !hideFollowingTab {
      res.append("following")
    }
    if showDigest {
      res.append("digest")
    }
    res.append("inbox")
    if !showDigest {
      res.append("profile")
    }
    return res
  }

  var body: some View {
    VStack(spacing: 0) {
      WindowLink(level: .alert, transition: .move(edge: .bottom), isPresented: $showOperationToast) {
        OperationToast(operationMessage: $operationMessage,
                       showOperationToast: $showOperationToast,
                       operationStatus: $operationStatus)
      } label: {
        EmptyView()
      }.buttonStyle(.plain)

      if let pushLinkRequest = pushLinkRequest {
        PresentationLink(
          transition: PresentationLinkTransition.slide(
            options: PresentationLinkTransition.SlideTransitionOptions(
              edge: .trailing,
              options: PresentationLinkTransition.Options(
                modalPresentationCapturesStatusBarAppearance: true,
                preferredPresentationBackgroundColor: ThemeManager.currentBgColor
              ))),
          isPresented: $presentPushContainer,
          destination: {
            WebReaderLoadingContainer(requestID: pushLinkRequest)
              .background(ThemeManager.currentBgColor)
              .environmentObject(dataService)
              .environmentObject(audioController)
          }, label: {
            EmptyView()
          }
        )
      }

      TabView(selection: $selectedTab) {
        if !hideFollowingTab {
          NavigationView {
            HomeFeedContainerView(viewModel: followingViewModel, isEditMode: $isEditMode)
              .navigationBarTitleDisplayMode(.inline)
              .navigationViewStyle(.stack)
          }.tag("following")
        }

        if showDigest, #available(iOS 17.0, *) {
          NavigationView {
            DigestView(dataService: dataService)
              .navigationBarTitleDisplayMode(.inline)
              .navigationViewStyle(.stack)
          }.tag("digest")
          NavigationView {
            HomeFeedContainerView(viewModel: inboxViewModel, isEditMode: $isEditMode)
              .navigationBarTitleDisplayMode(.inline)
              .navigationViewStyle(.stack)
          }.tag("inbox")
        } else {
          NavigationView {
            HomeFeedContainerView(viewModel: inboxViewModel, isEditMode: $isEditMode)
              .navigationBarTitleDisplayMode(.inline)
              .navigationViewStyle(.stack)
          }.tag("inbox")
          NavigationView {
            ProfileView()
              .navigationViewStyle(.stack)
          }.tag("profile")
        }

      }
      if audioController.itemAudioProperties != nil {
        MiniPlayerViewer()
          .onTapGesture {
            showExpandedAudioPlayer = true
          }
          .padding(0)
        Color(hex: "#3D3D3D")
          .frame(height: 1)
          .frame(maxWidth: .infinity)
      }
      if isEditMode != .active {
        CustomTabBar(
          displayTabs: displayTabs,
          selectedTab: $selectedTab)
          .padding(0)
      }
    }
    .sheet(isPresented: $showExpandedAudioPlayer) {
      ExpandedAudioPlayer(
        delete: {
          showExpandedAudioPlayer = false
          audioController.stop()
          currentViewModel?.removeLibraryItem(dataService: dataService, objectID: $0)
        },
        archive: {
          showExpandedAudioPlayer = false
          audioController.stop()
          currentViewModel?.setLinkArchived(dataService: dataService, objectID: $0, archived: true)
        },
        viewArticle: { itemID in
          if let article = try? dataService.viewContext.existingObject(with: itemID) as? Models.LibraryItem {
            currentViewModel?.pushFeedItem(item: article)
          }
        }
      )
    }
    .navigationBarHidden(true)
    .onReceive(NSNotification.performSyncPublisher) { _ in
      Task {
        await syncManager.syncUpdates(dataService: dataService)
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PushLibraryItem"))) { notification in
      guard let libraryItemId = notification.userInfo?["libraryItemId"] as? String else { return }
      pushLinkRequest = libraryItemId
      presentPushContainer = true
    }
    .onOpenURL { url in
      inboxViewModel.linkRequest = nil

      withoutAnimation {
        NotificationCenter.default.post(Notification(name: Notification.Name("PopToRoot")))
      }

      if let deepLink = DeepLink.make(from: url) {
        switch deepLink {
        case let .search(query):
          inboxViewModel.searchTerm = query
        case let .savedSearch(named):
          if let filter = inboxViewModel.findFilter(dataService, named: named) {
            inboxViewModel.appliedFilter = filter
          }
        case let .webAppLinkRequest(requestID):

          DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) {
            inboxViewModel.pushLinkedRequest(request: LinkRequest(id: UUID(), serverID: requestID))
          }
        }
      }
      selectedTab = "inbox"
    }
  }
}
