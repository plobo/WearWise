# WearWise --- iOS AI Wardrobe Intelligence

## Implementation Plan

**Project type:** Native iOS application\
**Platform:** iOS 26+\
**Language:** Swift 6\
**UI:** SwiftUI\
**Architecture:** MVVM with Clean Architecture principles\
**Persistence:** SwiftData + local file storage\
**AI:** Apple Foundation Models\
**Computer vision:** Vision + Core Image\
**Backend:** None for the MVP\
**AI API keys:** None

------------------------------------------------------------------------

## 1. Product vision

WearWise is a privacy-first, on-device AI wardrobe assistant. It helps
people create a digital catalogue of clothes they already own,
understand each item's attributes, and eventually assemble outfits from
their actual wardrobe.

The product must not behave like a generic chatbot or recommend
imaginary items. The wardrobe database is the source of truth. AI may
interpret user preferences, extract attributes, and explain styling
suggestions, while deterministic application code validates item
availability and recommendation constraints.

### Product promise

**Know your wardrobe. Discover your style.**

### Primary goals

1.  Let users add clothing using the camera or photo library.
2.  Use Apple's on-device Foundation Models to suggest structured
    clothing attributes.
3.  Let users review and correct AI-generated attributes before saving.
4.  Store clothing records and photos locally.
5.  Browse, search, filter, and organize a digital wardrobe.
6.  Build a foundation for outfit recommendations using only owned
    items.

### Non-goals for the first release

-   User accounts, cloud sync, or a backend.
-   Paid AI services or third-party LLM APIs.
-   Shopping integrations or product purchasing.
-   Social feeds, public profiles, or sharing.
-   Virtual try-on or generated images of the user wearing clothes.
-   Automatic claims about fabric composition, brand, fit, or garment
    quality when these cannot be reliably inferred from the image.
-   Weather integration in the initial MVP.

------------------------------------------------------------------------

## 2. Target user and core use cases

### Target user

Someone who wants to organize their existing wardrobe, find combinations
they may not have considered, and make more intentional clothing
decisions.

### Core user journeys

#### Journey A --- Add an item

1.  Open My Wardrobe.
2.  Tap Add Clothing.
3.  Capture a photo or choose an existing photo.
4.  Crop or adjust the image if needed.
5.  Run on-device image analysis.
6.  Review suggested category, colour, pattern, style, and occasion
    attributes.
7.  Edit any incorrect or uncertain values.
8.  Save the item.
9.  See it in the wardrobe catalogue.

#### Journey B --- Browse the wardrobe

1.  Open My Wardrobe.
2.  Browse a visual grid of clothing.
3.  Filter by category, colour, season, or occasion.
4.  Search by item name or attributes.
5.  Open an item to view and edit its details.

#### Journey C --- Prepare for outfit intelligence

The user selects a collection of owned items and supplies an occasion
and style preference. The future Outfit Studio uses only those item IDs
and validates every returned ID against the local wardrobe.

------------------------------------------------------------------------

## 3. MVP scope

Build the MVP before implementing the full product vision.

### Included in MVP

-   SwiftUI application shell and five-tab navigation.
-   Discover landing screen with useful empty states.
-   My Wardrobe visual grid.
-   Add clothing from PhotosPicker and camera where available.
-   Local image storage.
-   Clothing item details and editing.
-   Foundation Models availability detection.
-   Image-based structured attribute suggestions where supported.
-   Manual entry and editing when AI is unavailable.
-   Category and colour filtering.
-   Local persistence using SwiftData.
-   Unit tests for domain logic and repositories.
-   Graceful error, loading, and empty states.

### Deferred until after MVP

-   Background removal.
-   Similar-item detection using Vision feature prints.
-   Outfit generation and AI tool calling.
-   Outfit calendar and usage tracking.
-   Personal style profile learning.
-   Wardrobe analytics and gap analysis.
-   Speech-based item entry.
-   Weather-aware recommendations.
-   iCloud sync or other synchronization.

### MVP acceptance criteria

The MVP is complete when:

-   A user can add an item without AI.
-   A compatible device can request AI-generated attribute suggestions.
-   AI failure or unavailability never blocks manual item entry.
-   Users can correct every AI-suggested attribute.
-   Items and photos remain available after app relaunch.
-   Users can browse, search, and filter saved items.
-   No network connection or external API key is required for core
    functionality.
-   Tests cover critical domain rules and persistence behaviour.

------------------------------------------------------------------------

## 4. Navigation and screen map

Use a five-tab `TabView`.

  -----------------------------------------------------------------------
  Tab                     Purpose                 MVP status
  ----------------------- ----------------------- -----------------------
  Discover                Wardrobe overview and   Basic
                          recently added items    

  My Wardrobe             Catalogue, search,      Full MVP
                          filters, item details   

  Outfit Studio           Outfit creation and     Placeholder
                          recommendations         

  Insights                Wardrobe statistics     Placeholder

  Style Profile           User preferences and    Basic preferences
                          app settings            
  -----------------------------------------------------------------------

### Screen inventory

#### Discover

-   Welcome or summary header.
-   Total wardrobe item count.
-   Recently added items.
-   Quick Add Clothing action.
-   Empty state with an explanation of how to begin.

#### My Wardrobe

-   Adaptive clothing grid.
-   Search field.
-   Category filter.
-   Colour filter.
-   Sort options: recently added, name, category.
-   Empty and no-results states.

#### Add Clothing

-   Camera entry point.
-   Photo library entry point.
-   Image preview.
-   Analyse with AI action.
-   Manual entry alternative.
-   Analysis progress and error states.

#### Review Clothing

-   Image preview.
-   Editable item name.
-   Category and subcategory.
-   Primary and secondary colours.
-   Pattern.
-   Sleeve or garment-length attributes when relevant.
-   Suggested style and occasions.
-   Save and cancel actions.
-   Clear indication that AI suggestions need user confirmation.

#### Clothing Detail

-   Large image.
-   Item attributes.
-   Edit and delete actions.
-   Favourite toggle.
-   Future usage-history section.

#### Style Profile

-   Preferred styles.
-   Preferred colours.
-   Common occasions.
-   Comfort or fit preferences.
-   Privacy and AI availability information.

------------------------------------------------------------------------

## 5. Technical architecture

Use a feature-oriented structure with clear boundaries between
presentation, domain, data, and platform services.

``` text
WearWise/
├── App/
│   ├── WearWiseApp.swift
│   ├── AppDependencies.swift
│   └── RootTabView.swift
│
├── Core/
│   ├── AI/
│   │   ├── AIService.swift
│   │   ├── FoundationModelsService.swift
│   │   ├── AIAvailabilityManager.swift
│   │   ├── ClothingAnalysisPrompt.swift
│   │   └── AIError.swift
│   │
│   ├── Vision/
│   │   ├── ImageProcessor.swift
│   │   ├── DominantColorAnalyzer.swift
│   │   └── SimilarityAnalyzer.swift
│   │
│   ├── Persistence/
│   │   ├── ModelContainerFactory.swift
│   │   └── LocalImageStore.swift
│   │
│   ├── DesignSystem/
│   │   ├── Colors.swift
│   │   ├── Typography.swift
│   │   ├── Spacing.swift
│   │   └── Components/
│   │
│   └── Utilities/
│
├── Domain/
│   ├── Models/
│   │   ├── ClothingItem.swift
│   │   ├── ClothingAttributes.swift
│   │   ├── ClothingCategory.swift
│   │   ├── ClothingColor.swift
│   │   ├── ClothingOccasion.swift
│   │   └── StylePreferences.swift
│   │
│   ├── Repositories/
│   │   └── ClothingRepository.swift
│   │
│   └── UseCases/
│       ├── AddClothingItemUseCase.swift
│       ├── UpdateClothingItemUseCase.swift
│       ├── DeleteClothingItemUseCase.swift
│       ├── SearchWardrobeUseCase.swift
│       └── AnalyzeClothingImageUseCase.swift
│
├── Data/
│   ├── Repositories/
│   │   └── SwiftDataClothingRepository.swift
│   └── Mappers/
│
├── Features/
│   ├── Discover/
│   ├── Wardrobe/
│   ├── AddClothing/
│   ├── ClothingDetail/
│   ├── OutfitStudio/
│   ├── Insights/
│   └── StyleProfile/
│
└── WearWiseTests/
    ├── DomainTests/
    ├── RepositoryTests/
    ├── AITests/
    └── FeatureTests/
```

### Architecture rules

1.  SwiftUI views must not call Foundation Models directly.
2.  View models coordinate use cases and expose presentation state.
3.  Domain models must not depend on SwiftUI, SwiftData, or Foundation
    Models.
4.  AI output is a suggestion, not persisted truth until confirmed by
    the user.
5.  Repository protocols belong at the domain boundary.
6.  Platform-specific frameworks are isolated behind services.
7.  Use dependency injection through an app composition root.
8.  Keep image bytes out of SwiftData records; store image files locally
    and persist stable relative paths or identifiers.
9.  Avoid unnecessary abstraction. Introduce protocols where they enable
    testing, substitution, or meaningful separation.

------------------------------------------------------------------------

## 6. Data model

Start with a practical clothing model. Keep attributes explicit enough
for filtering and outfit matching.

### ClothingItem

Suggested fields:

  -----------------------------------------------------------------------
  Field                   Type                    Notes
  ----------------------- ----------------------- -----------------------
  id                      UUID                    Stable identifier

  name                    String                  User-editable display
                                                  name

  category                ClothingCategory        Required

  subcategory             String?                 Optional

  primaryColor            ClothingColor           Required or
                                                  user-confirmed

  secondaryColors         \[ClothingColor\]       Optional

  pattern                 String?                 Solid, striped,
                                                  checked, floral, etc.

  styleTags               \[String\]              Casual, formal, smart
                                                  casual, etc.

  occasions               \[ClothingOccasion\]    Optional

  seasonTags              \[String\]              Suggestions, not hard
                                                  facts

  imagePath               String                  Relative local file
                                                  path

  isFavorite              Bool                    User-controlled

  dateAdded               Date                    Creation date

  dateModified            Date                    Last modification

  aiAnalysisStatus        AIAnalysisStatus        Pending, completed,
                                                  unavailable, failed,
                                                  edited
  -----------------------------------------------------------------------

### Initial categories

-   Tops
-   Bottoms
-   Dresses
-   Outerwear
-   Shoes
-   Accessories
-   Activewear
-   Other

Use a category enum for stable application logic. Keep less predictable
descriptive attributes as editable strings or controlled tag values.

### Important modelling decisions

-   Do not infer a brand unless it is visibly present and legible.
-   Do not claim exact fabric composition from an ordinary photograph.
-   Allow multiple colours and occasions.
-   Make AI confidence optional and do not treat model-reported
    confidence as calibrated probability.
-   Preserve the user's edits if an item is analysed again.
-   Use explicit schema migrations when the SwiftData model changes.

------------------------------------------------------------------------

## 7. Foundation Models implementation

### Objective

Use Apple's on-device language model to produce structured clothing
descriptions from a clothing image and a carefully designed instruction.

### Responsibilities

`AIService` should provide an application-level interface such as:

``` swift
protocol AIService {
    func analyzeClothing(
        imageData: Data
    ) async throws -> ClothingAnalysisResult
}
```

The concrete Foundation Models implementation should:

1.  Check model availability.
2.  Create a session with a focused system instruction.
3.  Prepare a suitably sized image input.
4.  Request structured output.
5.  Validate and map the generated result.
6.  Return a domain-friendly result.
7.  Translate framework errors into application-level errors.

### Structured generation

Explore Apple's `@Generable` and `@Guide` APIs.

The generated result should include:

-   Suggested name.
-   Category.
-   Subcategory.
-   Primary colour.
-   Secondary colours.
-   Pattern.
-   Style tags.
-   Possible occasions.
-   Optional visible garment details.

Use constrained enums or guided fields for values that must match
application categories.

Illustrative pseudocode:

``` swift
@Generable
struct ClothingAnalysisResult {
    @Guide(description: "Short descriptive clothing name")
    var name: String

    @Guide(description: "One supported wardrobe category")
    var category: String

    @Guide(description: "Main visible colour")
    var primaryColor: String

    @Guide(description: "Visible pattern, if identifiable")
    var pattern: String

    @Guide(description: "Suggested style tags")
    var styleTags: [String]
}
```

Treat this as a design sketch. Confirm exact macro and multimodal input
APIs against the installed Xcode SDK documentation before
implementation.

### Prompt design principles

-   Ask only for information visible in the image.
-   Return unknown or uncertain values as unknown rather than inventing
    them.
-   Do not infer material, price, brand, size, or fit without evidence.
-   Use a controlled vocabulary for categories and colours where
    practical.
-   Keep the prompt focused on one clothing item.
-   Do not ask the model to generate an outfit during item
    classification.
-   Validate every generated value before showing it in the UI.

### AI availability and fallback

Foundation Models availability is not guaranteed on every device or at
every moment.

Handle: - Model unavailable on the device. - Apple Intelligence not
enabled or not ready. - Model still downloading or preparing. -
Unsupported input. - Generation failure. - Cancellation. - Invalid or
incomplete output. - Context or generation limits.

Manual entry must always remain available. Show a useful message rather
than silently failing.

### AI privacy

-   Process images locally through supported Apple frameworks.
-   Do not upload wardrobe photographs.
-   Do not log image data or personal wardrobe descriptions.
-   Make it clear when AI analysis is unavailable.
-   Keep all AI functionality optional.

------------------------------------------------------------------------

## 8. Image processing and Vision

Implement image processing as separate capabilities rather than coupling
them to the language model.

### MVP image pipeline

1.  Receive image from PhotosPicker or camera.
2.  Normalize orientation.
3.  Resize to a practical analysis size.
4.  Encode or prepare the image input supported by the model.
5.  Save an optimized local image.
6.  Generate a thumbnail for the wardrobe grid.
7.  Persist the image reference.

### Post-MVP Vision capabilities

#### Background removal

Explore Vision foreground-instance segmentation APIs available in the
deployment SDK. Use the result to create a clean transparent clothing
image where the subject can be segmented successfully.

Do not assume every photograph has a removable background. Preserve the
original image and provide a fallback.

#### Similarity detection

Explore `VNGenerateImageFeaturePrintRequest` and feature-print
comparisons to identify visually similar wardrobe items.

Use similarity as a discovery aid, not a definitive duplicate detector.

#### Colour analysis

Use Core Image or a custom pixel-sampling pipeline to estimate dominant
colours.

-   Ignore transparent pixels.
-   Consider excluding background regions.
-   Map measured colours to user-friendly names.
-   Let users correct the colour label.

------------------------------------------------------------------------

## 9. Outfit intelligence --- post-MVP milestone

This is the main differentiating feature after the digital wardrobe
works.

### Recommendation pipeline

Do not pass the entire wardrobe image collection to the language model.

Instead:

1.  Collect occasion, style, weather (if supplied), and user
    preferences.
2.  Filter wardrobe items deterministically.
3.  Build a compact candidate list containing item IDs and relevant
    attributes.
4.  Ask Foundation Models to select compatible combinations from the
    candidate list.
5.  Parse structured output.
6.  Validate that all IDs exist and satisfy application constraints.
7.  Display the outfit and an explanation.
8.  Capture user feedback.

### Outfit result

An outfit should contain:

-   Stable outfit ID.
-   Selected clothing item IDs.
-   Occasion.
-   Style description.
-   Short recommendation explanation.
-   User rating or feedback.
-   Date created.

### Critical validation

The model must never introduce a clothing item that does not exist in
the wardrobe.

If a generated ID is unknown, duplicated, or incompatible with the
required outfit structure, reject or repair the result.

### Future AI tools

Explore the Foundation Models `Tool` protocol for narrowly scoped
actions such as:

-   Search wardrobe by category.
-   Find items by colour.
-   Retrieve favourites.
-   Retrieve style preferences.
-   Get recent outfit history.

Tools should return only the information needed for the current request.

------------------------------------------------------------------------

## 10. Design system

### Visual direction

Use a premium fashion-editorial aesthetic.

-   Warm ivory or neutral background.
-   Charcoal typography.
-   Muted accent colours.
-   Large clothing photography.
-   Minimal card borders.
-   Generous spacing.
-   Subtle transitions.
-   Clear typography hierarchy.

### UI principles

-   The clothing photograph is the primary visual element.
-   Avoid cluttered dashboard widgets.
-   Use adaptive grids.
-   Provide accessible labels and hints.
-   Support Dynamic Type.
-   Support VoiceOver and sufficient colour contrast.
-   Never communicate a clothing attribute using colour alone.
-   Make AI-generated fields visually distinguishable from
    user-confirmed fields.

### Design system components

-   `PrimaryButton`
-   `SecondaryButton`
-   `ClothingCard`
-   `ClothingGrid`
-   `CategoryChip`
-   `ColorSwatch`
-   `AttributeRow`
-   `EmptyStateView`
-   `LoadingStateView`
-   `AIStatusView`
-   `ConfirmationBanner`

------------------------------------------------------------------------

## 11. Concurrency and performance

Use Swift 6 concurrency intentionally.

-   Keep UI state on `@MainActor`.
-   Use async functions for AI and image processing operations.
-   Use actors for shared mutable services where appropriate.
-   Avoid blocking the main thread with image decoding or processing.
-   Support cancellation when a user leaves an analysis screen.
-   Prevent duplicate analysis requests for the same operation.
-   Use bounded concurrency for batch operations.
-   Do not create unstructured tasks without a clear lifecycle.
-   Avoid retaining large image buffers in view models.
-   Profile memory use when scrolling large wardrobe grids.

Use `TaskGroup` only when there are independent operations that benefit
from parallel execution. Do not parallelize model generations
indiscriminately.

------------------------------------------------------------------------

## 12. Testing strategy

### Domain tests

-   Category validation.
-   Attribute normalization.
-   Search and filtering.
-   Favourite state.
-   Outfit candidate filtering.
-   Outfit ID validation.
-   Handling missing attributes.

### Repository tests

-   Save and fetch items.
-   Update item attributes.
-   Delete item and associated image.
-   Handle missing image files.
-   Persistence across container recreation.
-   Migration behaviour.

### AI tests

Use a protocol-based fake AI service for deterministic unit tests.

Test: - Successful structured response. - Incomplete response. -
Unsupported category. - Invalid colour. - Model unavailable. -
Generation failure. - Cancellation. - User correction overriding
generated suggestions.

Do not make unit tests dependent on a live on-device model. Add optional
manual integration tests on compatible hardware.

### UI tests

-   Add item manually.
-   Add item using a sample image.
-   Review and edit AI suggestions.
-   Save and reopen an item.
-   Filter and search wardrobe.
-   Delete an item.
-   Use the app with AI unavailable.

------------------------------------------------------------------------

## 13. Milestone execution plan

### Milestone 0 --- Environment and technical validation

Tasks: - Confirm Xcode and SDK versions. - Create the iOS project. - Set
deployment target to iOS 26. - Verify Foundation Models availability on
a supported device. - Build a small multimodal proof of concept. -
Verify structured generation. - Verify PhotosPicker and local image
storage.

Exit criteria: a test screen can submit a clothing photograph to the
on-device model and display a structured response on supported hardware.

### Milestone 1 --- Application foundation

Tasks: - Build the app shell and tab navigation. - Implement design
tokens and shared components. - Define domain models and repository
protocols. - Configure SwiftData. - Implement local image storage. -
Implement manual clothing creation and editing. - Add the wardrobe grid
and item details.

Exit criteria: complete manual wardrobe workflow with local persistence.

### Milestone 2 --- AI clothing analysis

Tasks: - Implement AI availability manager. - Implement Foundation
Models service. - Define structured generated output. - Add image input
handling. - Implement prompt and output validation. - Build the
review-and-confirm UI. - Add manual fallback and failure states.

Exit criteria: a user can photograph clothing, review suggestions,
correct them, and save the result.

### Milestone 3 --- Wardrobe discovery

Tasks: - Add category and colour filters. - Add search and sorting. -
Add favourites. - Optimize thumbnails and image loading. - Add
accessibility support.

Exit criteria: users can efficiently navigate a growing wardrobe.

### Milestone 4 --- Vision enhancements

Tasks: - Add colour analysis. - Prototype foreground segmentation. -
Prototype visual similarity. - Compare performance and quality on
different image types.

Exit criteria: image enhancements work with sensible fallbacks.

### Milestone 5 --- Outfit Studio

Tasks: - Define outfit domain models. - Implement deterministic
candidate filtering. - Build the AI recommendation prompt. - Implement
structured outfit generation. - Validate returned IDs. - Add outfit
saving and feedback.

Exit criteria: recommendations use only existing wardrobe items.

### Milestone 6 --- Insights and release preparation

Tasks: - Add wardrobe statistics. - Add style preferences. - Add outfit
history. - Add automated tests. - Run accessibility checks. - Profile
performance and memory. - Test offline behaviour and AI
unavailability. - Prepare App Store screenshots and metadata.

Exit criteria: release candidate with no dependency on external AI
services.

------------------------------------------------------------------------

## 14. Claude Code working instructions

Use the following rules when implementing this project.

1.  Work milestone by milestone. Do not generate the entire application
    in one step.
2.  Read the existing project structure before modifying files.
3.  Confirm the current SDK APIs rather than guessing Foundation Models
    signatures.
4.  Compile after each meaningful implementation increment.
5.  Keep Swift 6 concurrency checks enabled and address warnings.
6.  Use protocols and dependency injection for services that need test
    doubles.
7.  Do not put business logic inside SwiftUI views.
8.  Do not add third-party packages unless explicitly approved.
9.  Do not add a backend, cloud database, or paid API.
10. Keep all clothing images local.
11. Add unit tests alongside domain and repository functionality.
12. Add useful error states and manual fallbacks.
13. Never treat AI-generated attributes as verified facts.
14. Do not implement future milestones prematurely.
15. At the end of each milestone, report:
    -   Files created or changed.
    -   Features implemented.
    -   Build and test results.
    -   Known limitations.
    -   Next milestone tasks.

### First Claude Code task

Start with Milestone 0 only.

Inspect the development environment and create a minimal technical proof
of concept that:

-   Builds for iOS 26.
-   Checks Foundation Models availability.
-   Accepts one clothing photograph.
-   Sends it to the on-device model using the current SDK-supported
    multimodal API.
-   Requests structured clothing attributes.
-   Displays the result.
-   Handles model unavailability and generation errors.

Do not build the full app until this proof of concept compiles and has
been tested on compatible hardware.

------------------------------------------------------------------------

## 15. Definition of success

WearWise succeeds as a portfolio project when it demonstrates:

-   Modern SwiftUI application architecture.
-   Swift 6 concurrency.
-   Practical use of Apple's Foundation Models.
-   Structured and validated AI output.
-   Multimodal image understanding.
-   Vision and Core Image integration.
-   Local-first data architecture.
-   Robust offline and model-unavailable handling.
-   Meaningful unit and UI tests.
-   Thoughtful accessibility and performance.

The strongest technical demonstration is not simply that AI can describe
a shirt. It is that the application combines on-device AI, computer
vision, structured data, deterministic validation, and excellent native
UX into a useful product.
