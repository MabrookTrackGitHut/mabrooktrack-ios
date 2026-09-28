# MabrookTrack iOS SDK

Install attribution and in-app events for TikTok app campaigns, by [MabrookTrack](https://mabrooktrack.com/#mmp). iOS 14+, Swift 5.9, no dependencies.

## Install

Swift Package Manager: **File → Add Package Dependencies…** → `https://github.com/MabrookTrackGitHut/mabrooktrack-ios` (from 0.1.0).

CocoaPods: `pod 'MabrookTrack', '~> 0.1'`

## Use

```swift
import MabrookTrack

// at app start
MabrookTrack.configure(MabrookConfig(appKey: "<APP KEY FROM YOUR DASHBOARD>", locale: "ar-SA"))

// where it fits your onboarding (iOS shows the tracking prompt)
MabrookTrack.requestTrackingAuthorization { status in }

// after login
MabrookTrack.setUser(email: email, phone: phone, externalId: customerId)

// events
MabrookTrack.viewContent(["product_id": "SKU-1"])
MabrookTrack.addToCart(["product_id": "SKU-1", "value": 199])
MabrookTrack.trackPurchase(MabrookPurchase(value: 199, currency: "SAR", orderId: order.id))
MabrookTrack.generateLead(["form": "contact"])
MabrookTrack.track("any_custom_event", properties: ["k": "v"])
```

Info.plist:

```xml
<key>NSUserTrackingUsageDescription</key>
<string>Used only to measure ad effectiveness</string>
<key>NSAdvertisingAttributionReportEndpoint</key>
<string>https://mmp.mabrooktrack.com</string>
```

The SDK registers the app for SKAdNetwork and updates the conversion value after purchases (schema is owned server-side). Do not update SKAdNetwork values from your own code.

Privacy: IDFA only after the user allows tracking; email/phone hashed at MabrookTrack's edge; `MabrookTrack.setConsent(.denied)` stops all sends. A privacy manifest is included.

The full step-by-step guide, with the event mapping to TikTok, is in your MabrookTrack dashboard.
