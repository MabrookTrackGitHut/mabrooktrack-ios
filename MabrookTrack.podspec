Pod::Spec.new do |s|
  s.name         = "MabrookTrack"
  s.version      = "0.1.0"
  s.summary      = "MabrookTrack iOS SDK — install attribution and in-app events for TikTok app campaigns."
  s.homepage     = "https://mabrooktrack.com/#mmp"
  s.license      = { :type => "Commercial", :text => "See https://mabrooktrack.com/terms" }
  s.authors      = { "VM MEDIA LLC" => "hello@mabrooktrack.com" }
  s.platforms    = { :ios => "14.0" }
  s.swift_version = "5.9"
  s.source       = { :git => "https://github.com/MabrookTrackGitHut/mabrooktrack-ios.git", :tag => s.version.to_s }
  s.source_files = "Sources/MabrookTrack/**/*.swift"
  s.resource_bundles = { "MabrookTrack" => ["Sources/MabrookTrack/PrivacyInfo.xcprivacy"] }
  s.frameworks   = "AdSupport", "AppTrackingTransparency", "StoreKit"
end
