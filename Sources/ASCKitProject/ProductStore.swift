import Foundation

/// Every in-app purchase a project holds, read from disk and not yet checked.
///
/// This says what is there, including things that should not be. The validator
/// decides what is wrong, so a window can open on a project with one broken
/// file instead of refusing to open at all.
public struct ProductCatalog: Sendable {
    /// Keyed by product id, which is also the file name.
    public let products: [String: Product]

    /// Files that could not be read at all, with the reason.
    public let unreadable: [String: String]

    /// Files whose `productId` field disagrees with their file name. The file
    /// name wins, and the validator says so.
    public let misnamed: [String: String]

    /// Subscription group files, keyed by reference name.
    public let groups: [String: SubscriptionGroup]

    /// Group files that could not be read at all, with the reason.
    public let unreadableGroups: [String: String]

    public init(
        products: [String: Product] = [:],
        unreadable: [String: String] = [:],
        misnamed: [String: String] = [:],
        groups: [String: SubscriptionGroup] = [:],
        unreadableGroups: [String: String] = [:]
    ) {
        self.products = products
        self.unreadable = unreadable
        self.misnamed = misnamed
        self.groups = groups
        self.unreadableGroups = unreadableGroups
    }

    /// In the order they read, which is by product id.
    public var sorted: [Product] {
        products.values.sorted { $0.productID < $1.productID }
    }

    public var sortedGroups: [SubscriptionGroup] {
        groups.values.sorted { $0.referenceName < $1.referenceName }
    }

    /// Every group a subscription names or a file holds, by name.
    ///
    /// A subscription can name a group that has no file yet. That group still
    /// needs its words, so it is here too.
    public var groupNames: [String] {
        let named = products.values
            .filter { $0.resolvedKind?.isAutoRenewable == true }
            .compactMap(\.subscriptionGroup)
            .filter { $0.isEmpty == false }
        return Set(named).union(groups.keys).sorted()
    }

    /// The subscriptions that name this group, by product id.
    public func subscriptions(in groupName: String) -> [Product] {
        sorted.filter {
            $0.resolvedKind?.isAutoRenewable == true && $0.subscriptionGroup == groupName
        }
    }

    public var isEmpty: Bool {
        products.isEmpty && unreadable.isEmpty && groups.isEmpty && unreadableGroups.isEmpty
    }
}

/// Reads the products folder. Reports what is there and judges nothing.
public enum ProductStore {
    /// The silence file lives in this folder, beside the products, because a
    /// silence goes with the thing it is about. It is not a product, so no
    /// product may be called this.
    public static let silenceFileName = "silenced"

    /// The folder inside the products folder that holds one file per
    /// subscription group. The product files never read a folder.
    public static let groupsFolderName = "groups"

    /// Never throws. A missing folder is a project with no products yet, which
    /// is every project until somebody adds one.
    public static func load(in project: Project) -> ProductCatalog {
        var products: [String: Product] = [:]
        var unreadable: [String: String] = [:]
        var misnamed: [String: String] = [:]

        let decoder = JSONDecoder()
        for file in jsonFiles(in: project.productsURL) {
            let name = file.deletingPathExtension().lastPathComponent
            guard name != silenceFileName else { continue }

            do {
                var loaded = try decoder.decode(Product.self, from: Data(contentsOf: file))
                // The file name wins, the way it does for a language file. A
                // `productId` that disagrees is reported rather than followed,
                // because the file name is what a person reads.
                if loaded.productID != name {
                    misnamed[name] = loaded.productID
                    loaded.productID = name
                }
                products[name] = loaded
            } catch {
                unreadable[name] = "\(error)"
            }
        }

        var groups: [String: SubscriptionGroup] = [:]
        var unreadableGroups: [String: String] = [:]
        for file in jsonFiles(in: project.subscriptionGroupsURL) {
            let name = file.deletingPathExtension().lastPathComponent
            do {
                var loaded = try decoder.decode(SubscriptionGroup.self, from: Data(contentsOf: file))
                loaded.referenceName = name
                groups[name] = loaded
            } catch {
                unreadableGroups[name] = "\(error)"
            }
        }

        return ProductCatalog(
            products: products,
            unreadable: unreadable,
            misnamed: misnamed,
            groups: groups,
            unreadableGroups: unreadableGroups
        )
    }

    /// A group name that cannot be a file name. Nil when the name is fine.
    public static func reasonToRefuse(groupName: String) -> String? {
        if groupName.isEmpty {
            return String(localized: "A subscription group name cannot be empty.", bundle: .module)
        }
        if groupName.contains("/") || groupName.contains(":") {
            return String(
                localized: "A subscription group name cannot hold a slash or a colon, because it is the file name.",
                bundle: .module
            )
        }
        if groupName.hasPrefix(".") {
            return String(
                localized: "A subscription group name cannot start with a dot, because the file would be hidden.",
                bundle: .module
            )
        }
        return nil
    }

    /// A product id that cannot be a file name, or that would collide with the
    /// silence file. Nil when the id is fine.
    public static func reasonToRefuse(productID: String) -> String? {
        if productID.isEmpty {
            return String(localized: "A product id cannot be empty.", bundle: .module)
        }
        if productID == silenceFileName {
            return String(localized: """
            \(silenceFileName).json is where silenced warnings go, so no product \
            can be called that.
            """, bundle: .module)
        }
        if productID.contains("/") || productID.contains(":") {
            return String(
                localized: "A product id cannot hold a slash or a colon, because it is the file name.",
                bundle: .module
            )
        }
        if productID.hasPrefix(".") {
            return String(
                localized: "A product id cannot start with a dot, because the file would be hidden.",
                bundle: .module
            )
        }
        return nil
    }

    private static func jsonFiles(in directory: URL) -> [URL] {
        DirectoryListing.files(in: directory)
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
