# Hetkia

English \| [简体中文](README_CN.MD)

This project is licensed under the [MIT License](LICENSE).

The screenshots below are a little out of date. I'll refresh them when I
get around to it; they predate the Hugo integration and image hosting
workflow.

### Why I built this

When WeChat began accessing more personal data, I became concerned that
things like Moments history and private messages could potentially be
used for AI training or other purposes. As someone who has long
preferred to keep personal diary-like posts hidden from other people, I
found that prospect unsettling.

I've used Hexo and Hugo for years to publish articles on my own sites,
so I extended my Hugo workflow with short posts for quick thoughts and
the occasional rant.

In practice, I tend to divide what I share into a few categories:

1.  **Short Posts** --- a sentence or paragraph, usually without images;
    a place for quick thoughts or the occasional rant.
2.  **Essays** --- journal-like writing and reflections, with or without
    photos.
3.  **Experiences** --- knowledge and lessons I want to preserve and
    share.
4.  **Fiction** --- a personal hobby.

The way I publish each type of content is different:

-   Short Posts should be quick to publish from a phone, without having
    to worry about formatting.
-   Essays should be just as easy to publish. They may include photos,
    and I might write them on either my phone or computer, though I use
    my phone more often.
-   Experiences and fiction are better written and published on a
    computer.

Both Hexo and Hugo can be part of a workflow that requires pushing
content to a Git repository. Doing that from a phone is inconvenient,
but a small dedicated app makes the process much simpler.

I've also always liked the "On This Day" feature in some apps. It groups
photos taken on the same calendar day across different years. I enjoy
looking back at old photos and remembering what was happening at the
time. I never quite understood why Apple didn't offer this as a built-in
feature.

Eventually, I revoked broad photo-library access for the other app and
allowed access only to a few selected photos, so I could no longer use
that feature there.

That gave me the idea for an app of my own: **Hetkia**.

Hetkia is an iOS photo-memory and journaling app centered on **On This
Day**. The home screen brings together photos taken on the same month
and day in previous years, based on the device's local calendar.
Browsing reads from PhotoKit and loads images from the system as needed.
Journals, photo associations, and JPEG previews are saved on the device
only when you create a journal, edit and save its text, or post a note.

### Privacy and sharing

Hetkia offers a few different ways to keep or share your memories:

-   **Private journals:** Full journal entries stay on your iPhone.
    Hetkia does not sync them through iCloud. The iPad version has not
    been thoroughly tested; it mainly includes layout adaptations, such
    as a two-column home screen.
-   **Image sharing:** Choose a few photos from a day, arrange them into
    a collage with your own words, and export a journal-style image card
    to share with selected people.
-   **Blog publishing:** Publish an Essay with optional photos, or a
    text-only Short Post, to your Hugo project through GitHub. GitHub
    Actions can then build and deploy your site. In this project, Essays
    map to the Hugo "essays" section; you can change the paths to match
    your own site structure.
-   **Text-only posts:** You can also publish a plain-text Short
    Post---a quick thought or rant---without selecting any photos.

Hetkia also supports a publishing workflow for static sites such as Hugo
and Hexo. From the Home Screen widget, you can start a Short Post or
Essay with a single tap. Once configured, the app handles the publishing
steps: it uploads photos to Cloudflare R2, inserts their CDN URLs into
the Markdown files, commits the files to your private GitHub repository,
and triggers GitHub Actions to publish your site. You can focus on
selecting photos and writing.

GitHub Pages and Cloudflare R2 settings are built in. If you use the
same setup, you can enter your own values and get started. Using other
hosting providers or CDNs may require code changes.

## Features

-   On first launch, the app explains why it needs full photo-library
    access and requests permission. Once access is granted, it scans
    photos from today and matching dates in previous years, displays
    progress, and opens the home screen automatically.
-   The home screen shows only **On This Day**. Photos fill each card,
    with the date overlaid in white. All eligible photos are shown in a
    dynamic-height collage built on a one-third grid. Layouts avoid
    empty cells, including when the number of photos is even.
-   Journal details support photo viewing, full-screen paging, place
    maps, image sharing, journal editing, on-device AI drafts, notes,
    and optional **remote publishing** (Hugo Essays with optional
    images, or text-only Short Posts). When publishing an Essay, you can
    choose **now** or **photo capture date** as the site's `date`.
    Publishing does not automatically save the journal on the device.
    GitHub tokens and R2 keys are stored in the device Keychain;
    repository paths and the CDN domain are configured under Settings →
    Publish service. After a successful publish, the publishing sheet
    closes; connection-test results appear below the relevant settings
    card.
-   Journal text and notes are stored separately. An AI draft card
    appears above the notes area; applying a draft asks for confirmation
    if journal text already exists. Browsing alone does not create a
    saved journal or JPEG preview.
-   A floating bar at the bottom of the root screen switches between
    **Home** (On This Day) and **History** (journals saved on the
    device). In History, **Month / Year / All** switch between browsing
    levels: the complete list, a two-column year view, a two-column
    month view for a selected year (each card shows year and month), and
    the two-column journal list for a selected month. The bottom bar
    handles navigation between levels; there is no in-list back control
    or swipe-back navigation. Tapping **History** again returns to the
    complete list. The bar is hidden on the journal detail screen.
-   History reads only from local SwiftData. Card images fill the
    available area, with the date or year-month and entry count overlaid
    in white.
-   The large Home Screen widget creates a full-bleed collage using the
    first image from each matching-date entry. It displays up to **nine
    entries**, arranged in a one-third-grid collage, and prioritizes
    photos with GPS coordinates. When there are two images, it uses one
    full-size background image with a smaller image overlaid. The title
    and brand name appear over the images. StandBy and small widgets use
    an image-only collage. Each image can deep-link to its corresponding
    journal.
-   Notes can be edited or deleted. If the last note is deleted and the
    journal has no body text or AI draft, the app also deletes the empty
    journal and its associated photo previews.
-   The AI prompt can be viewed and customized in Settings. The default
    prompt asks for a 2--5 sentence entry based on the photos and
    metadata, written in the current system language and without
    specific dates. Prompts are limited to 1,500 user-visible
    characters. If the limit is exceeded, saving is blocked and an alert
    is shown.
-   Photos, Live Photos, and videos can appear in the app. Screenshots
    and screen recordings are excluded by default and can be enabled in
    Settings; when enabled, regular camera media is prioritized. Hidden
    photos are not shown. Items in "Recently Deleted" are not included
    in standard PhotoKit library queries.
-   Supported languages: Simplified Chinese, Traditional Chinese,
    English, Spanish, and Thai.

Text over photos is always white, with a subtle dark gradient to
maintain contrast. WidgetKit may adapt widget rendering to the display
context, but it does not automatically choose text colors based on each
photo's brightness. Journal details and shared journal images use the
same one-third-grid collage layout. Detail-card height adapts to the
collage, while the shared image retains the date and time.

## Platforms and AI

-   iPhone and iPad only. The minimum deployment target is **iOS/iPadOS
    18**. macOS and Mac Catalyst are not supported.
-   Non-AI features---including photo access, system thumbnails, local
    journal storage, maps, sharing, and WidgetKit---are available on iOS
    18.
-   Journal text generation with Apple Foundation Models requires iOS 26
    or later, a supported device, and a model that is ready to use. The
    app checks the OS version and model status when you request
    generation. Image-understanding input additionally requires iOS 27
    or later.

Background refresh is scheduled by the system on a best-effort basis; it
is not guaranteed to run exactly at midnight. When the app is in the
foreground, it refreshes by querying PhotoKit.

The home screen first displays the local photo-index cache for the
current date. When the cache is valid, a normal launch queries only the
current year's photos for today. Pulling down on the home screen forces
a full scan across all years. The first launch, and the first launch
after a new day, also trigger a full scan.

On a warm launch, the home screen keeps the cached cards visible while
querying photos from the current year. It publishes new results only
when the dates or photo identifiers have changed, avoiding a full redraw
when the content is unchanged. An in-process scan coordinator combines
concurrent requests that have the same date, time zone, filter settings,
and scan scope. An in-progress full scan can satisfy a narrower
current-year query; a narrower query cannot replace a full scan
requested by the user. Results are committed by generation number, so
stale dates or older batches cannot overwrite a newer index. The
progress indicator appears only during the initial full scan and a
user-requested full refresh.

A full scan still queries PhotoKit by date for media from 1900 through
the current year, even if local journals already exist. A saved journal
does not mean that no new photos have been added for that anniversary.
The complete set of photos associated with a journal also serves a
different purpose from the prioritized set shown on the home screen.
Journal persistence keeps its existing triggers and write behavior; a
home-cache hit does not skip photo associations or JPEG preview
generation required by an explicit user action.

The main app and Widget Extension run in separate processes. The main
app writes a lightweight widget index through the App Group, and the
widget restores photos by resource identifier. If the snapshot is stale
or a photo is unavailable, the widget falls back to its own PhotoKit
query. The main app's scan coordinator is not shared across processes,
avoiding concurrent SwiftData writes from the widget and the main app.

## Screenshots

| Empty home state | Journal details |
| --- | --- |
| ![On This Day empty state](screenshot/home-empty-state.jpg) | ![Journal detail](screenshot/journal-detail.jpg) |

| Home Screen widget | Shared journal image |
| --- | --- |
| ![Widget on the Home Screen](screenshot/widget-home-screen.jpg) | ![Shared journal image](screenshot/share-journal.jpg) |

| Saved Journals | Settings |
| --- | --- |
| ![Saved Journals](screenshot/saved-journals.jpg) | ![Settings](screenshot/settings.jpg) |

More reference screens, including widget collage layouts and
journal-detail actions, are in [`screenshot/`](screenshot/).

## Build

``` sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

See the [product requirements](docs/PRODUCT_REQUIREMENTS.md) for
complete product behavior and the [development
guide](docs/DEVELOPMENT.md) for implementation details and verification
notes.

The repository does not contain API keys or deployment secrets.
Configure GitHub and R2 credentials on the device only.

## Repository layout

``` text
Hetkia-Starter/
├── Hetkia.xcodeproj/            # App and WidgetKit extension targets
├── Hetkia/                      # SwiftUI app, onboarding, details, PhotoKit, settings, publishing, and localization
├── HetkiaWidget/                # On This Day WidgetKit extension
├── Design/                      # Design source files
├── screenshot/                  # Compressed reference screenshots named by content
└── docs/                         # Product requirements and development guide
```

The README files provide an overview in English and Simplified Chinese.
Detailed product behavior and implementation guidance are maintained in
the linked documents. Reference screenshots are organized in
`screenshot/` by home screen, details, settings, saved journals,
widgets, and shared images.
