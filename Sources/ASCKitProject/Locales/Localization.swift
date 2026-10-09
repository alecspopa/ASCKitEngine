import Foundation

/// Where this target keeps its words.
///
/// A `LocalizedStringResource` looks in the main bundle unless it is told
/// otherwise, and the main bundle here is the app. A sentence written in this
/// target would fall back to the source language and never translate, with no
/// error to say so.
extension LocalizedStringResource.BundleDescription {
    static var here: Self { .atURL(Bundle.module.bundleURL) }
}
