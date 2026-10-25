# Hetkia

English | [简体中文](README_CN.MD)

Hetkia is an iOS photo-memory app centered on “On This Day.” The home screen shows photo groups captured on the same month and day in previous years, using the device’s local date. Browsing reads PhotoKit and displays system-provided images as needed. A journal, photo links, and JPEG previews are saved locally only when the user generates a journal, edits and saves its text, or posts a message.

## Features

- The first launch explains and requests full access to the photo library. After access is granted, the app scans today and matching dates from previous years, shows progress, and opens the home screen automatically.
- The home screen shows only “On This Day.” Photos fill each card, with the date overlaid in white. Photo collages use layouts of 1, 3, 5, 7, or 9 images.
- Journal details support photo viewing, full-screen paging, place maps, share images, journal editing, on-device AI drafts, and messages. Journal text and messages are stored separately. An AI draft appears above the message board; applying it asks for confirmation if journal text already exists. Browsing alone does not create a saved journal or JPEG preview.
- “Saved Journals” in Settings reads only locally saved records, grouped by year and month in a two-column grid. Card images fill the available area, with dates and photo counts overlaid in white.
- The large Home Screen widget creates a full-bleed collage from the first image of each matching-date group. It shows up to three years in a one- or three-image layout and prioritizes photos with GPS coordinates. The title and brand name overlay the image. StandBy and small widgets use an image-only collage. Each image can deep-link to its corresponding journal.
- Personal messages can be edited or deleted. If the last message is deleted and the journal has no body text or AI draft, the empty journal and its linked photo previews are deleted as well.
- The AI prompt can be reviewed and customized in Settings. The default asks for a 2–5 sentence entry grounded in the photos and metadata, written in the current system language without specific dates. Prompts are limited to 1,500 user-perceived characters; Save displays an alert and is blocked above the limit.
- Photos, Live Photos, videos, screenshots, and screen recordings can appear. Regular camera photos are preferred; screenshots and recordings are not excluded. Hidden items are omitted. Items in “Recently Deleted” are not included in standard PhotoKit library fetches.
- Supported languages: Simplified Chinese, Traditional Chinese, English, Spanish, and Thai.

Text over photos uses white with a subtle dark gradient for contrast. WidgetKit may adapt widget rendering to the display context, but it does not automatically choose text color based on each image’s brightness. Journal detail cards show “Keep the ordinary days in Hetkia” and the brand name above the content; the date and time appear in the navigation bar. Shared journal images use a separate layout and retain their date and time.

## Platforms and AI

- iPhone and iPad only. The minimum deployment target is **iOS/iPadOS 18**; macOS and Mac Catalyst are not supported.
- Non-AI features—including photo access, system thumbnails, local journal storage, maps, sharing, and WidgetKit—are available on iOS 18.
- Journal text generation with Apple Foundation Models requires iOS 26 or later, a supported device, and a ready model. The app checks the OS version and model availability when the user requests generation. Image understanding input requires iOS 27 or later.

Background refresh is scheduled on a best-effort basis by the system and is not guaranteed to run exactly at midnight. When the app is active, it refreshes by querying PhotoKit.

The home screen first displays the local photo-index cache for the current date. When the cache is valid, a regular launch queries only the current year’s photos for today. Pulling down on the home screen forces a full scan across all years. The first scan and the first launch after a new day also scan all years.

## Build

```sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See the [product requirements](docs/PRODUCT_REQUIREMENTS.md) for the complete product behavior and the [development guide](docs/DEVELOPMENT.md) for implementation details and verification notes.

## Repository layout

```text
Hetkia-Starter/
├── Hetkia.xcodeproj/            # App and WidgetKit extension targets
├── Hetkia/                      # SwiftUI app, onboarding, details, PhotoKit, settings, and localization
├── HetkiaWidget/                # On This Day WidgetKit extension
├── Design/                      # Design source files
├── screenshot/                  # Reference screenshots named by content
└── docs/                        # Product requirements and development guide
```

The README files provide an English and Simplified Chinese overview; detailed product behavior and implementation guidance are maintained in the linked documents. Reference screenshots are organized in `screenshot/` by home screen, details, settings, saved journals, widgets, and share images.
