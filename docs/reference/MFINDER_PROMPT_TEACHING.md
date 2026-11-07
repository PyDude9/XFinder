# MFinder — Teaching Prompts for Claude
## Learn the Engineering Behind Each Feature (Systems Engineer Perspective)

> These prompts teach you *how the engineering works*, not just how to copy code.
> Ask Claude to teach you first, then ask it to implement.

---

## HOW TO USE

1. Copy a **Teaching Prompt** below.
2. Paste it into Claude (no system prompt needed — these are your message).
3. Read and ask follow-up questions.
4. After you understand, use the matching **System Prompt** in `PROMPT_SYSTEM.md` to implement.

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 1 — HOW DISK STORAGE ANALYSIS WORKS
## (Treemap / Sunburst / File Tree Scanner)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how a disk storage analyzer app works from a systems engineering perspective.
I want to understand the full pipeline — not just the code — so explain WHY each design choice exists.

Cover these topics in order:

1. FILE SYSTEM TRAVERSAL
   - What is a directory tree? How does the OS expose it to apps?
   - What is the difference between inode, file name, path, and file descriptor?
   - Why is recursive directory listing slow on spinning hard drives and fast on SSDs?
   - What is the difference between file size, allocated size, and logical size? Why do these differ?
   - What are hard links and APFS clones, and why do they make "total disk used" tricky to calculate correctly?
   - On macOS specifically, what APIs exist for directory traversal? (FileManager, NSDirectoryEnumerator, fts_open, opendir/readdir, getattrlistbulk) — what are the tradeoffs in speed and permissions?

2. BACKGROUND THREADING MODEL
   - Why can you NEVER do file I/O on the main thread in a GUI app?
   - What is the difference between a thread, a queue, a task, and an actor in Swift?
   - How does Swift Concurrency (async/await + Task) solve the callback hell of older DispatchQueue code?
   - What is cooperative cancellation, and how do you implement a cancel button that actually stops the scan?
   - How do you safely send scan progress updates to the UI thread from a background thread without data races?

3. TREEMAP ALGORITHM
   - What is a treemap? Who invented it and why?
   - Explain the "squarified treemap" algorithm step by step. What does "squarified" mean and why does it produce better-looking rectangles than a simple row-based layout?
   - What is "aspect ratio" in this context, and why do we minimize it?
   - How do you map a file's byte size to a pixel rectangle area, given a target bounding box of W×H pixels?
   - Walk me through the recursive case: given a folder with 5 children of sizes [500MB, 300MB, 100MB, 60MB, 40MB] inside a 800×600 rect, show me how the algorithm would split them.

4. SUNBURST CHART ALGORITHM
   - What is a sunburst chart? How is it related to a pie chart and a treemap?
   - How do you map a file tree to concentric arcs? What does each ring represent?
   - What math converts a "fraction of parent's size" into "start angle + end angle"? (Hint: fraction × 2π)
   - What is the coordinate system for drawing arcs in Core Graphics / Canvas?
   - How do you decide when a segment is too small to draw a label? What geometric property do you check?

5. RENDERING PERFORMANCE
   - If a folder has 100,000 files, should you draw 100,000 rectangles? Why not?
   - What is "level of detail" (LOD) culling and how does it apply to treemaps?
   - What is the difference between CPU rendering (Core Graphics) and GPU rendering (Metal / OpenGL)? When is each appropriate for a 2D chart?
   - How does egui (Rust) or SwiftUI Canvas differ from retained-mode UI frameworks like UIKit in terms of when and how drawing happens?

After explaining each topic, give me a concrete analogy from real life (not from programming) to make it stick.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 2 — HOW DUPLICATE DETECTION WORKS
## (Hashing, Perceptual Hash, Parallel Processing)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how a duplicate file finder works at a systems engineering level.
I want to understand WHY each step is designed the way it is, not just copy code.

Cover these topics:

1. THE FUNDAMENTAL PROBLEM
   - Two files are "identical" if their bits are the same. How do we check this efficiently for 500,000 files?
   - Naive approach: compare every file to every other file (N²). Why is this too slow? Calculate: at 1 GB/s read speed, how long would it take to compare all pairs in a 1 TB drive?
   - Optimization: why do we first group files by SIZE before reading any content?

2. CRYPTOGRAPHIC HASHING
   - What is a hash function? What properties make SHA-256 suitable for identifying duplicate files?
   - What is a "collision" in hashing? Could two different files ever have the same SHA-256 hash? How likely is it?
   - What is streaming hashing? Why do we NOT load the entire file into RAM at once?
   - Explain how you would compute SHA-256 of a 10 GB file efficiently: chunk size, loop structure, memory footprint.
   - Why do some tools use xxHash or BLAKE3 instead of SHA-256? What is the tradeoff between speed and collision resistance for a duplicate finder (not a security application)?

3. PARALLEL HASHING
   - Why can we hash multiple files at the same time?
   - What is the difference between CPU parallelism (multiple cores) and I/O parallelism (reading from NVMe)?
   - What is "I/O-bound" vs "CPU-bound" work? Which category is file hashing? How does that affect how many threads you should use?
   - What is TaskGroup in Swift Concurrency and how does it fan out parallel work and collect results?
   - What happens if you spawn 100 parallel file reads from the same SSD? Is faster always better? What is "queue depth" in NVMe context?

4. PERCEPTUAL HASHING FOR IMAGES
   - Cryptographic hash: flipping 1 pixel changes the hash completely. Why is this bad for finding "visually similar" photos?
   - What is a perceptual hash (pHash)? How does the DCT (Discrete Cosine Transform) relate to it?
   - Walk me through the pHash algorithm step by step:
     a. Resize image to 32×32 greyscale (why greyscale? why 32×32?)
     b. Compute 2D DCT
     c. Take the top-left 8×8 region (why top-left? what does "low frequency" mean for images?)
     d. Compute the median value
     e. For each of the 64 values: 1 if above median, 0 if below → 64-bit integer
   - What is Hamming distance? How do you use it to say "these two images are 90% similar"?
   - Why does pHash work for resized, re-compressed, or slightly cropped duplicates?

5. THE PIPELINE AS A SYSTEM
   - Draw the data flow: [File List] → [Group by Size] → [Hash Groups] → [pHash Images] → [Results]
   - What data structure would you use at each stage? (HashMap, Set, Vec, BTreeMap — explain why)
   - How do you display incremental results to the user as hashing progresses? (don't wait for all 500K files)
   - What is "back pressure" in a producer-consumer pipeline? How do you prevent one stage from flooding the next?

Give me a real-world analogy for each concept (not programming metaphors — everyday life examples).
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 3 — HOW ENCRYPTION & SECURE CONTAINERS WORK
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how an encrypted file container works at a systems engineering and cryptography level.
I'm learning software engineering, not just copying code. Explain the "why" behind every design decision.

Cover these topics:

1. WHAT ENCRYPTION ACTUALLY DOES
   - What is symmetric encryption? What is asymmetric encryption? Which one is used for file containers and why?
   - Explain AES (Advanced Encryption Standard): what is a block cipher? What does "256-bit key" mean in practice?
   - What is AES-GCM mode? What does "GCM" (Galois/Counter Mode) add compared to basic AES? Why do we care about authentication (the G part) and not just encryption?
   - What is an IV (Initialization Vector)? Why must it be random? What happens if the same IV is used twice with the same key?

2. KEY DERIVATION FROM PASSWORD
   - A user's password is short and guessable. A cryptographic key must be 256 bits and unpredictable. How do you safely turn one into the other?
   - What is PBKDF2? Walk me through it: PBKDF2(password, salt, iterations=100000, PRF=HMAC-SHA256) → 32 bytes key.
   - What is the SALT and why is it stored in the file header (not secret)?
   - Why does increasing iterations make brute-force attacks harder? Calculate: at 1 billion guesses/second, how long does it take to brute-force an 8-character lowercase password with and without 100,000 PBKDF2 iterations?
   - What is Argon2id and why is it considered better than PBKDF2 for password hashing?

3. THE CONTAINER FILE FORMAT
   - Design a file format header for an encrypted container. What MUST go in the header (not encrypted)? What must NEVER go in the header?
   - Typical layout: [Magic bytes 4B] [Version 1B] [Algorithm ID 1B] [Salt 32B] [IV 12B] [Ciphertext...] [Auth Tag 16B]
   - Why are "magic bytes" (like a file signature) useful? What purpose do they serve?
   - Why is the ciphertext's length equal to the plaintext's length in GCM mode? (Stream cipher behavior)
   - After decryption, how does GCM verify that the ciphertext hasn't been tampered with? What is an authentication tag?

4. KEYCHAIN AND TOUCH ID
   - What is the macOS Keychain? Why is it safer than storing passwords in a file or UserDefaults?
   - What is a Keychain Access Control? How does "require Touch ID to retrieve this secret" work at the OS level?
   - What is the Secure Enclave on Apple Silicon? What data never leaves it?
   - For our container: should we store the PASSWORD or the DERIVED KEY in Keychain? What is the security tradeoff?

5. SECURE MEMORY HANDLING
   - Why is it dangerous to store a password as a Swift String? (Hint: Swift strings are value types that copy)
   - What is `memset_s` and why do you use it instead of `memset`?
   - What is "zeroing on dealloc" and how does Data(bytesNoCopy:...) help?
   - What is Secure Input on macOS? Why can't Keyboard Clean work while Secure Input is active? (They operate at the same CGEventTap level)

Give me analogies from everyday life for each concept. No code yet — I want to understand the system design first.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 4 — HOW FILE SEARCH & SPOTLIGHT WORK
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how full-text file search and AI-powered semantic search work at a systems engineering level.
Focus on the "how the machine does it" perspective, not just the API calls.

Cover these topics:

1. THE BASIC SEARCH PROBLEM
   - Searching for a filename: why is a simple directory walk O(N) and slow for 1M files?
   - What is an index? Give an everyday analogy (a book's index vs. reading every page).
   - What is an inverted index? Draw the data structure for indexing these 3 file names:
     "vacation_photo_2023.jpg", "tax_return_2023.pdf", "photo_backup.zip"
   - How does Spotlight build and maintain this index? What is FSEvents and why does Spotlight need it to know when files change?

2. NSMetadataQuery AND SPOTLIGHT
   - NSMetadataQuery is Apple's API to query Spotlight's index. What is in Spotlight's index? (file name, content, metadata attributes like kMDItemKind, kMDItemContentModificationDate, kMDItemTextContent)
   - What is the difference between kMDItemDisplayName CONTAINS[cd] and kMDItemTextContent CONTAINS[cd]? Which one requires Spotlight to index file contents?
   - What is "cd" in an NSPredicate? (case-insensitive, diacritic-insensitive)
   - Why is Spotlight fast even for text content search? (Hint: inverted index + tokenization)
   - What is tokenization? Give an example: "Tax Return 2023" → what tokens does Spotlight store?

3. SEMANTIC / AI SEARCH
   - Keyword search fails for: "find photos of my cat". What if the filename is "IMG_4821.jpg"?
   - What is an embedding? Turn the concept "cat photo" into a vector of numbers — how does this allow similarity search?
   - What is a vector database / index (like FAISS or Apple's own semantic index)? How is it different from a B-tree index?
   - What is "cosine similarity" between two embedding vectors? Give the intuition (not the formula).
   - Walk me through how Apple Intelligence indexes your files:
     a. User writes a document "Planning our trip to Paris"
     b. A CoreML embedding model runs ON DEVICE and produces a 512-float vector
     c. The vector is stored in an index on disk
     d. User searches "Europe vacation plans" → query is embedded → nearest-neighbor search → file is found
   - Why does "nearest-neighbor search" in high-dimensional space (512 dimensions) need special algorithms (HNSW, FAISS) instead of a simple sorted list?

4. PARSING NATURAL LANGUAGE QUERIES
   - User types: "pdf files from last week". How do you turn this into a structured query?
   - Design a simple intent parser:
     - "pdf files" → kind: [pdf]
     - "from last week" → dateField: modified, dateRange: (now - 7 days, now)
     - "large files" → size > 100 MB
   - What is named entity recognition (NER)? How would it identify "last week" as a time reference?
   - From MFinder's binary: "pdf files from last week" → { kinds: [pdf], dateField: modified, dateRange: lastWeek, keywords: [] }
     What data structure is this? Design it in Swift (a struct/enum).

5. INDEX MAINTENANCE
   - After indexing 500,000 files, a new file is added. How do you update the index without rebuilding it from scratch?
   - What is an FSEvents stream? How do you register for file system change notifications?
   - What is a "checkpoint" in the context of an incremental index? Why does MFinder store one?
   - What happens if the user deletes a file that is in the index? (stale entries — how do you clean them?)

No code yet. Teach me the concepts with analogies.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 5 — HOW ARCHIVE COMPRESSION WORKS
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how file compression and archive formats work from a systems engineering perspective.
I want to understand the fundamental ideas, not just how to call an API.

Cover these topics:

1. WHY COMPRESSION WORKS
   - What is information entropy? Why can a truly random file NOT be compressed?
   - Files have patterns (repeated words in a document, repeated pixel colors in an image). Give 3 concrete examples of patterns in real files.
   - What is the theoretical minimum size a file can be compressed to? (Shannon entropy bound — give intuition, not formula)

2. LOSSLESS COMPRESSION ALGORITHMS
   - LZ77/LZ78 family (used in ZIP, gzip, zstd, 7z):
     - What is a "sliding window"? Give a concrete example with the string "ABCABCABC".
     - How does LZ77 encode "ABCABC" as a back-reference to "ABC"? Draw it out.
     - What is the "dictionary" in LZ-based compression?
   - Huffman coding:
     - What is variable-length encoding? Why do frequent bytes get shorter codes?
     - Build a simple Huffman tree for the string "AABBCBAA" (by hand, step by step).
   - DEFLATE = LZ77 + Huffman. How do ZIP files use DEFLATE?
   - 7-Zip uses LZMA2. What makes LZMA faster/better than DEFLATE for large files?

3. ARCHIVE FORMAT DESIGN
   - A ZIP file is a container. What is the difference between a compression algorithm and an archive format?
   - ZIP structure: [Local file header + compressed data] × N files + [Central directory at end of file]
   - Why is the central directory at the END of a ZIP file, not the beginning? (Hint: think about streaming writes and append operations)
   - What is a solid archive (7z default)? Why does it compress better than per-file compression for many small similar files?
   - What is the difference between ZIP (random access) and TAR.GZ (stream)?

4. STREAMING VS BUFFERED I/O
   - MFinder bundles its own 7-Zip engine. Why bundle a binary instead of using the system ZIP?
   - For large files (10 GB video), why do we compress in a streaming fashion (read 1MB chunks, compress, write) rather than loading the entire file?
   - What is "read-ahead" buffering? How does the OS prefetch data for sequential reads?

5. PROCESS ISOLATION (why MFinder uses an external binary)
   - What is a child process? Why is it safer to run 7zz as a separate process than to link its code into the main app?
   - If 7zz crashes processing a corrupt archive, the main app survives. How?
   - How do you launch a subprocess in macOS (Process/NSTask), pipe its stdout for progress, and kill it on cancel?
   - What is stdio (stdin, stdout, stderr)? How do you read progress output from a command-line tool in real time?

Teach me with analogies. Then show me ONE concrete example (the LZ77 string compression), step by step, by hand.
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 6 — HOW PERMISSIONS & SANDBOXING WORK ON MACOS
## (Applies to ALL features above)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how macOS app permissions, sandboxing, and privacy work at a systems engineering level.
MFinder uses many sensitive permissions: Accessibility, Screen Recording, Full Disk Access.
I want to understand what these actually mean at the OS level.

Cover these topics:

1. WHAT IS A SANDBOX?
   - In computer security, what is a "sandbox"? Give an everyday analogy.
   - On macOS, every App Store app is sandboxed. What does this mean concretely? List 5 things a sandboxed app CANNOT do without permission.
   - What is the kernel's role in enforcing the sandbox? (MAC framework, TrustedBSD, Sandbox.framework)
   - What is an entitlement? Where are they stored in an app bundle?

2. FILE SYSTEM PERMISSIONS (for Disk Analyzer and Duplicate Finder)
   - What is "Full Disk Access" (FDA)? What does it grant? What does the OS check when an app tries to read ~/Library?
   - What is a Security-Scoped Bookmark? Why do you need it to persist access to a user-chosen folder across app restarts?
   - When a user opens a file via NSOpenPanel, what "grant" does the OS give the app? How long does it last?
   - What is `startAccessingSecurityScopedResource()` and why must you call `stopAccessingSecurityScopedResource()` when done?
   - If an app tries to read /etc/passwd, what happens? Walk me through the kernel's permission check path.

3. ACCESSIBILITY PERMISSION (for Window Snapping, Keyboard Clean, Screenshot shortcuts)
   - What is AXUIElement? Why does controlling other windows require a special "Accessibility" trust grant?
   - Why is Accessibility permission considered so sensitive? (An Accessibility-trusted app can read screen content, control the UI of ANY app, and simulate user input.)
   - How does `AXIsProcessTrusted()` work? Where does macOS store the list of trusted apps?
   - What is a CGEventTap? At what level of the OS does it intercept events? (Session-level, before they reach any app)
   - Why does Keyboard Clean conflict with Secure Input? (Both operate on CGEvents; Secure Input prevents any tap from seeing keystrokes in a password field.)

4. SCREEN RECORDING PERMISSION (for Screenshot feature)
   - Why does capturing the screen require a separate permission from Accessibility?
   - What does `CGDisplayCreateImage()` do at the OS level? Why does it need Screen Recording entitlement?
   - What is the difference between capturing your own app's window (always allowed) vs. capturing other apps' windows (requires Screen Recording)?

5. KEYCHAIN (for Secure Lock and Cloud credentials)
   - What is the macOS Keychain? Who owns it? (The user's login session, encrypted with the user's login password)
   - What is a Keychain item? What attributes does it have? (kSecClass, kSecAttrService, kSecAttrAccount, kSecValueData)
   - What is an Access Control on a Keychain item? How do you require Touch ID to access a specific item?
   - What is the Secure Enclave? What operations does it perform? What NEVER leaves it?
   - What does kSecAttrSynchronizable = false mean? Why would you set it for a local encryption key?

6. PRIVACY DATA TYPES (Contacts, Photos, Microphone, Camera)
   - MFinder does NOT access these, but explain: for each privacy data type on macOS, what is the user-facing permission dialog, what API triggers it, and where is the grant stored?
   - What is TCC (Transparency, Consent, and Control)? How does the TCC database work?
   - What happens if an app tries to access Photos without permission? What error code / exception is thrown?

7. PUTTING IT TOGETHER: TRUST MODEL FOR MFINDER-LIKE APPS
   - MFinder integrates a Finder Sync Extension (MFinderSync.appex). Extensions run in a separate process from the main app. How do they communicate? (NSXPCConnection)
   - Why do some permissions (Full Disk Access) require the user to manually grant them in System Settings, rather than showing an automatic dialog?
   - What is the difference between a sandboxed and a non-sandboxed app on macOS? Which distribution channel requires sandboxing? (Mac App Store = required, direct distribution = optional but required for Hardened Runtime)

Teach me with concrete analogies (security guard, filing cabinet, etc.). After each concept, tell me: "If you get this wrong in a real app, what breaks or what security hole opens?"
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 7 — HOW A SYSTEM MONITOR WORKS
## (CPU, Memory, Disk I/O, Network, Battery)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how a system resource monitor (like Activity Monitor or MFinder's system monitor) works at a systems engineering level.
I want to understand how the OS exposes hardware information to apps.

Cover these topics:

1. CPU USAGE
   - What is a CPU "tick"? What are user ticks, system ticks, idle ticks?
   - CPU % is not an instantaneous measurement — it's a RATE over time. How do you calculate CPU % from two successive snapshots of tick counts?
   - What is host_processor_info() in macOS? What kernel call does Activity Monitor use?
   - What is "per-core" CPU usage? How does the OS distribute work across cores?
   - What is hyperthreading (Intel) or Efficiency Cores (Apple Silicon)? How does the kernel scheduler use them?

2. MEMORY
   - macOS memory types: wired, active, inactive, compressed, free. What does each mean?
   - What is memory compression? Why does macOS compress RAM instead of immediately paging to disk?
   - What is "memory pressure"? How does the kernel decide to compress memory vs. free inactive pages vs. swap to disk?
   - What is virtual memory? Why does Activity Monitor show apps using MORE RAM than the physical RAM on the system?
   - What API reads VM stats? (host_statistics64 with HOST_VM_INFO64_COUNT)

3. DISK I/O
   - What is disk throughput (MB/s) vs. IOPS (I/O operations per second)? Which matters more for a file scan?
   - What is an I/O queue? When you call read() on 10 files simultaneously, what happens in the kernel?
   - How does IOKit expose disk statistics? What is "IOBlockStorageDriver" and what properties does it have?
   - What is "read-ahead" prefetching? How does the OS automatically speed up sequential reads?
   - SSD vs. HDD: why is random I/O on an HDD hundreds of times slower than on an SSD?

4. NETWORK
   - What is a network interface (en0, en1, lo0)? How does the OS count bytes sent/received per interface?
   - What is getifaddrs() and what does it return? How do you use it to read network stats?
   - Net rate = (bytes_now - bytes_before) / elapsed_time. Why do you need TWO samples to compute a rate?
   - What is a "socket"? How do you find which app owns which socket? (proc_pidinfo with PROC_PID_FD_INFO)

5. BATTERY
   - What is IOKit? How does it expose battery state?
   - What is a "power source" in macOS terms (kIOPSLocalBatteryType)?
   - What data is available: charge %, max capacity, cycle count, temperature, charging state, time remaining estimate.
   - How does the OS estimate "time remaining"? (It's a moving average of recent discharge rate × remaining capacity)
   - What is "battery health %"? (currentMaxCapacity / designCapacity × 100). Why does this decrease over time?

6. DISPLAY AND REFRESH TIMING
   - A system monitor updates every 1 second. How do you implement a 1-second timer without blocking the UI thread?
   - What is a circular buffer (ring buffer)? Draw one for storing 60 seconds of CPU readings.
   - How does a sparkline graph work? (Just an array of floats plotted as connected line segments, scaled to min-max range)
   - What is "jitter" in a timer? Why might a 1-second timer fire at 1.05s or 0.98s? Does this matter for a system monitor?

Teach me with analogies. After each concept, tell me: "What would break if you got this wrong?" and "What tool would you use to debug it?"
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## TOPIC 8 — HOW EVENT-DRIVEN GUI APPS WORK
## (The architecture behind every feature above)
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Teaching Prompt

```
Teach me how a macOS GUI application works at a systems engineering level.
I keep hearing "don't block the main thread" but I want to understand WHY, and how the whole event system is built.

Cover these topics:

1. THE MAIN RUN LOOP
   - What is a run loop? Draw a diagram of what happens every frame in a GUI app.
   - What is an "event"? Give 5 examples of events a macOS app processes.
   - What is "blocking the main thread"? Why does sleeping for 1 second in the main thread freeze the UI completely?
   - What does "16ms per frame" (60 fps) mean for how much work you can do on the main thread between frames?

2. CONCURRENCY MODELS COMPARED
   - Callback hell (old Swift/ObjC): what is a completion handler? Why did deeply nested callbacks become a problem?
   - DispatchQueue / GCD (Grand Central Dispatch): what is a queue? What is the difference between serial and concurrent queues?
   - Combine (reactive): what is a Publisher and a Subscriber? Give a concrete example.
   - Swift Concurrency (async/await + actor): what is an actor? What problem does it solve vs. DispatchQueue + locks?
   - For a disk scanner that runs in the background and updates a progress bar: sketch the data flow using Swift Concurrency.

3. THE ACTOR MODEL AND DATA RACES
   - What is a data race? Give a concrete example with two threads modifying the same variable.
   - What is a mutex (lock)? What is a deadlock? Give an example.
   - What is an Actor in Swift? How does it prevent data races automatically?
   - What is `@MainActor`? Why do all UI updates need to run on the main actor?

4. RETAINED VS. IMMEDIATE MODE UI
   - What is retained-mode UI (AppKit / UIKit / SwiftUI)? The app describes "what the UI looks like"; the framework decides "when to redraw".
   - What is immediate-mode UI (egui / ImGui)? The app redraws the entire UI every frame; the framework draws what it's told.
   - For a treemap with 10,000 nodes: what are the performance tradeoffs of each approach?
   - What is "dirty rect" optimization? Why does retained-mode sometimes redraw less?

5. STATE MANAGEMENT
   - MFinder has many features (scanner, duplicate finder, archive, search…). How does a large app manage which panel is showing, what data is loaded, and what operations are in progress?
   - What is the Model-View-Controller (MVC) pattern? What problem does it solve?
   - What is the Model-View-ViewModel (MVVM) pattern that SwiftUI encourages? What is an ObservableObject?
   - For a disk scanner: sketch the state machine. States: Idle → Scanning → Done → Error. What transitions exist? What data is valid in each state?

6. MEMORY MANAGEMENT (ARC vs Rust ownership)
   - What is ARC (Automatic Reference Counting) in Swift?
   - What is a retain cycle? Give an example with a closure capturing self.
   - What is `[weak self]` in a closure? When MUST you use it?
   - For background tasks that hold references to UI objects: what happens if the user closes the window while a scan is running?
   - Rust's ownership model vs Swift's ARC: what problem does Rust solve that Swift ARC doesn't?

After each concept, give me a "break this rule and see what happens" example (concrete bugs from real apps).
```

---

## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
## COMBINED PROMPT: "Teach me everything, start to finish"
## ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Use this for a deep multi-session study

```
I'm learning software engineering seriously, with the vision of a systems engineer, not just vibe coding.
I'm studying the app MFinder, a macOS Finder companion with these main features:
- Disk Storage Analyzer (treemap + sunburst visualization)
- Duplicate File Finder (checksum-based + perceptual hash for images)
- Archive Manager (ZIP/7z with its own bundled engine)
- AI-powered file search (Spotlight + semantic embeddings)
- Folder Sync
- Encrypted containers (AES-256-GCM + Keychain + Touch ID)
- System Monitor (CPU / Memory / Disk / Network / Battery)
- Screenshot capture + OCR
- Window snapping
- Keyboard clean mode

I want you to be my systems engineering teacher for these topics. Here are the rules:

1. ALWAYS explain WHY before HOW. I want to understand the problem before the solution.
2. Use ANALOGIES from everyday life (not programming) to make concepts stick.
3. After each concept, tell me: "If you get this wrong, here's the specific bug or security hole that opens."
4. Connect concepts across topics: e.g., how does threading (Topic 7) relate to the scan engine (Topic 1)?
5. After explaining theory, show me ONE concrete worked example by hand (not code).
6. At the end of each topic, ask me a question to test my understanding. Wait for my answer before continuing.

Start with Topic 1: Disk Storage Analyzer. Begin with the most fundamental concept and build up.
```
