import MapKit
import SwiftUI
import UIKit

@available(iOS 18.0, *)
struct MapItemDetailCardView: UIViewControllerRepresentable {
    let mapItem: MKMapItem
    var showsInlineMap = false
    var ratingModel: RatingDisplayModel? = nil
    var onRatingEmbedded: ((Bool) -> Void)? = nil
    var onFinished: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> ContainerViewController {
        let controller = ContainerViewController(
            mapItem: mapItem,
            showsInlineMap: showsInlineMap,
            ratingModel: ratingModel,
            onRatingEmbedded: onRatingEmbedded
        )
        controller.update(mapItem: mapItem, showsInlineMap: showsInlineMap, ratingModel: ratingModel, coordinator: context.coordinator)
        return controller
    }

    func updateUIViewController(_ controller: ContainerViewController, context: Context) {
        context.coordinator.parent = self
        controller.update(mapItem: mapItem, showsInlineMap: showsInlineMap, ratingModel: ratingModel, coordinator: context.coordinator)
        controller.onRatingEmbedded = onRatingEmbedded
    }

    final class Coordinator: NSObject, MKMapItemDetailViewControllerDelegate {
        var parent: MapItemDetailCardView

        init(parent: MapItemDetailCardView) {
            self.parent = parent
        }

        func mapItemDetailViewControllerDidFinish(_ detailViewController: MKMapItemDetailViewController) {
            parent.onFinished?()
        }
    }

    final class ContainerViewController: UIViewController {
        private let detailController: MKMapItemDetailViewController
        private var cachedScrollView: UIScrollView?
        private var currentShowsInlineMap: Bool
        var onRatingEmbedded: ((Bool) -> Void)?

        init(mapItem: MKMapItem, showsInlineMap: Bool, ratingModel: RatingDisplayModel?, onRatingEmbedded: ((Bool) -> Void)?) {
            detailController = MKMapItemDetailViewController(mapItem: mapItem, displaysMap: showsInlineMap)
            currentShowsInlineMap = showsInlineMap
            self.onRatingEmbedded = onRatingEmbedded
            super.init(nibName: nil, bundle: nil)
            notifyEmbeddedState(for: ratingModel)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear

            addChild(detailController)
            detailController.view.backgroundColor = .clear
            view.addSubview(detailController.view)
            detailController.view.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                detailController.view.topAnchor.constraint(equalTo: view.topAnchor),
                detailController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                detailController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                detailController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
            detailController.didMove(toParent: self)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            adjustInsetsIfNeeded()
        }

        func update(mapItem: MKMapItem, showsInlineMap: Bool, ratingModel: RatingDisplayModel?, coordinator: Coordinator) {
            detailController.delegate = coordinator

            if detailController.mapItem != mapItem {
                detailController.mapItem = mapItem
            }

            if currentShowsInlineMap != showsInlineMap {
                currentShowsInlineMap = showsInlineMap
            }

            notifyEmbeddedState(for: ratingModel)
            adjustInsetsIfNeeded()
        }

        private func notifyEmbeddedState(for ratingModel: RatingDisplayModel?) {
            guard let onRatingEmbedded else { return }
            // Apple renders its detail card inside a private scene, so we cannot embed additional rows.
            // Always report `false` so the SwiftUI fallback can stay visible.
            if ratingModel != nil {
                onRatingEmbedded(false)
            }
        }

        private func adjustInsetsIfNeeded() {
            guard let scrollView = resolveScrollView() else { return }
            let bottomInset = view.safeAreaInsets.bottom + 16

            if abs(scrollView.contentInset.bottom - bottomInset) > .ulpOfOne {
                scrollView.contentInset.bottom = bottomInset
            }

            if abs(scrollView.verticalScrollIndicatorInsets.bottom - bottomInset) > .ulpOfOne {
                scrollView.verticalScrollIndicatorInsets.bottom = bottomInset
            }
        }

        private func resolveScrollView() -> UIScrollView? {
            if let cachedScrollView { return cachedScrollView }
            let scrollView = findScrollView(in: detailController.view)
            cachedScrollView = scrollView
            return scrollView
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let scrollView = view as? UIScrollView { return scrollView }
            for subview in view.subviews {
                if let scrollView = findScrollView(in: subview) {
                    return scrollView
                }
            }
            return nil
        }
    }
}
