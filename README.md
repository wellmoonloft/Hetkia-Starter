# Hetkia / 时光

[English](README.md) \| 简体中文

This project is licensed under the [MIT License](LICENSE).

The screenshots are from a fairly old version. I'll take new ones when I
feel motivated to do so. Back then, Hugo integration and the image
hosting service had not yet been integrated.

### Why I Built This

When WeChat started accessing personal information, I became concerned
that historical Moments posts, private messages, and other personal data
could potentially be used for AI training or other purposes. For someone
like me, who has long preferred to keep personal diary entries hidden
from others, this was practically a nightmare.

I've used Hexo for a long time and later switched to Hugo to publish
articles. I eventually extended my Hugo setup by adding a Quick Posts
feature for posting rants.

To sum it up, I think personal sharing generally falls into four
categories:

1.  **Rants** --- Quick Posts: just a sentence or a short paragraph,
    without images.
2.  **Essays** --- Journal-style entries: a paragraph with some personal
    thoughts, with or without images.
3.  **Experience** --- Sharing and preserving knowledge and things
    you've learned.
4.  **Fiction** --- This one is simply a personal hobby.

These different types of content also call for different publishing
methods.

For rants, I want to be able to grab my phone and post something on the
spot, without having to worry about formatting or anything like that.

Essays should be just as easy to publish. They may include longer
passages and sometimes images. I can write them on either my phone or
computer, although I'll probably use my phone more often.

Experience posts and fiction, on the other hand, are definitely better
written and published on a computer.

However, both Hexo and Hugo have one major drawback: publishing requires
a GitHub push. Doing that on a phone is rather cumbersome, but writing
my own app makes the process much simpler.

There's also a feature on Douyin that I've always liked: **On This
Day**. It organizes photos and brings together pictures taken on the
same calendar day in previous years. I really like this feature, and I
don't understand why Apple doesn't offer something similar itself.
Sometimes, looking through old photos brings back memories of the past.
Maybe that's just what happens as you get older.

But it's Douyin, after all. I had already revoked its access to my photo
library, allowing it access only to a few selected photos. So I could no
longer use that feature.

With that in mind, I started thinking about building an app to meet my
own needs. And that's how Hetkia came about.

**Hetkia (时光)** is an app that helps you write a journal based on your
photo memories. It gathers photos taken on the same calendar day across
different years into memory cards for you to browse and use as
inspiration for local journal entries. It also supports publishing
directly to static blogs such as Hugo and Hexo (requires GitHub
Actions).

Local journals are private. You can also turn them into journal-card
images and selectively share them with friends. In addition, you can use
home screen widgets to start publishing a Quick Post or an Essay to Hugo
with a single tap. The app takes care of the formatting. Once everything
is configured, all you need to do is choose your photos and write your
text.

It automatically uploads your images to an R2 image library, retrieves
their CDN URLs, and inserts those URLs into the content. It then
generates an MD file and uploads it to your private repository, where
GitHub Actions takes care of publishing.

From a privacy and security perspective, there are several layers.

The most private journals stay on your iPhone. I've never intended to
support iCloud synchronization, either. I haven't tested the iPad
version extensively, so it mainly includes basic adaptations, such as
displaying the home screen in two columns.

The next layer is image sharing. You can select several photos from a
particular day and combine them into a nicely arranged collage, add your
own text, and generate a journal image that you can share with others.

The next step is publishing journals and Quick Posts.

You can select photos, add a paragraph, and publish directly to your
Hugo project. GitHub Actions then deploys the content to your Hugo
website. In my setup, this corresponds to the Essays section, but you
can change that yourself.

You can also publish without selecting any photos. Just write something
like "Fuck that damn boss" and send it off as a rant.

I've already prepared the configurations for GitHub Pages and R2. If
you're using these two services, you can use the existing setup
directly. If you use another image host or Pages provider, you may need
to modify the code.

If you get stuck, just ask ChatGPT. It should be able to help you figure
things out.

## Features

-   The home screen displays On This Day photos and historical journal
    entries in two separate masonry-style lists. Historical journals can
    be browsed by year and month.
-   The journal detail page supports photo viewing, zooming and swiping
    between photos, location maps, journal editing, on-device AI drafts,
    comments, and journal sharing. Sharing combines the day's photos and
    journal text into a single image. It also supports optional **remote
    publishing**. To enable this, configure your GitHub repository and
    Cloudflare R2 image library in Settings. Your GitHub token and
    Cloudflare R2 credentials are stored in the system Keychain. The
    repository path and CDN are configured under Settings → Publishing
    Services.
-   Remote publishing supports text-only posts as well as posts with
    images. Images are automatically uploaded to the image library, and
    their returned CDN URLs are inserted into the post using Markdown
    syntax. The text editor does not provide Markdown shortcuts, so
    Markdown formatting must be entered manually if needed.
-   There are two types of home screen widgets:
    1.  **Large square widget:** Displays a collage of On This Day
        photos, with up to nine images. It can be placed on the home
        screen or in StandBy.
    2.  **Small square widget:** Provides two buttons: Publish an Essay
        (with images) and Publish a Quick Post (without images).
-   If your device supports Apple Foundation Models (iOS 26 or later),
    you can use AI on the journal detail page to analyze photos and
    generate journal text based on their content. Generation uses the AI
    prompt configured in Settings. The prompt is limited to 1,500
    characters. This is an app-level limit intended to help control
    token consumption during a single generation. Note that the context
    window of Apple Foundation Models is not fixed at 4,096 tokens; its
    capacity depends on the model and device. Apple's official
    demonstration of the next-generation on-device model in iOS 27
    showed a context window of 8,192 tokens. The prompt, photo inputs,
    and model output all consume part of the context window.
-   Photos, Live Photos, and videos can be included in the display.
    Screenshots and screen recordings are excluded by default, but you
    can enable them in Settings. When enabled, regular camera-captured
    media is prioritized. Hidden and recently deleted items are not
    included.
-   Supports Simplified Chinese, Traditional Chinese, English, Spanish,
    and Thai.

## Platforms & AI

-   Supports **iPhone and iPad only**. The minimum deployment target is
    **iOS/iPadOS 18**. macOS is not currently supported.
-   Non-AI features, including photo access, system-generated
    thumbnails, local journal storage, maps, sharing, and WidgetKit, are
    available on iOS 18.
-   Photo understanding with Foundation Models requires iOS 27 or later.
    Text-only journal generation remains available on iOS 26 and later.

Background refresh relies on the system's best-effort scheduling and is
not guaranteed to run exactly at midnight. Refreshing the app in the
foreground triggers a new PhotoKit query.

The home screen prioritizes the local photo index cache for the current
day. When the cache is valid, a normal app launch only queries photos
for today's date in the current year. Pulling down on the home screen
forces a full rescan across all years. A full scan is also performed on
first use or when no cache exists for a new day.

On a warm launch, the home screen retains its already displayed cached
cards while querying photos for the current year. New results are
published only when the date or photo identifiers have changed, avoiding
a full-screen redraw when the content remains unchanged. The in-process
scan coordinator merges concurrent requests that share the same date,
time zone, filter settings, and scan range. An ongoing full scan can
satisfy a narrower query for the current year, but a narrower query will
not replace a full scan requested by the user. Results are committed in
generation order, so requests for outdated dates or older batches cannot
overwrite newer indexes. The progress indicator is shown only during the
initial full scan and when the user manually triggers a full refresh by
pulling down.

A full scan still queries PhotoKit by date for media from every year
between 1900 and the present, even if local journals already exist. A
saved journal does not mean that no new photos have been added for that
year. The complete set of photos associated with a journal and the
prioritized set displayed on the home screen serve different purposes.
Journal persistence tasks retain their existing triggers and write
semantics. A cache hit on the home screen will not skip the photo
associations or JPEG preview generation required by user operations.

The main app and Widget Extension run as separate processes. The main
app writes a lightweight widget index through App Groups. The widget
first attempts to retrieve photos using their resource identifiers. If
the snapshot is invalid or a photo is unavailable, the widget falls back
to its own PhotoKit query. The main app's scan coordinator is not shared
across processes, avoiding concurrent writes to SwiftData from the
widget and the main app.

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

Additional reference images, including widget collage layouts and
detail-page actions, are available in [`screenshot/`](screenshot/).

## Build

``` sh
xcodebuild -project Hetkia.xcodeproj -scheme Hetkia -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

For complete product behavior, see the [Product
Requirements](docs/PRODUCT_REQUIREMENTS.md). For implementation
structure and verification records, see the [Development
Notes](docs/DEVELOPMENT.md). Please note that both documents were
generated by AI.

## Directory Structure

``` text
Hetkia-Starter/
├── Hetkia.xcodeproj/            # App and WidgetKit extension targets
├── Hetkia/                      # SwiftUI app, onboarding, detail views, PhotoKit, settings, publishing, and localization
├── HetkiaWidget/                # On This Day WidgetKit extension
├── Design/                      # Original design files
├── screenshot/                  # Compressed UI reference screenshots, organized by content
└── docs/                         # Product requirements and development notes
```

The product requirements and development notes document the complete app
behavior and implementation details. Screenshots can be browsed in
`screenshot/`, organized into home screen, detail views, settings, saved
journals, widgets, and shareable images.

