import Foundation

/// Shown once, on the very first launch, so a new user lands on something
/// inviting instead of a blank page.
enum Welcome {
    static let markdown = """
    # Welcome to Ouro MD

    A minimalist, themable, **native macOS** Markdown editor — write on the left of
    your mind, read on the right.

    ## The basics

    - Open a file with **⌘O**, or a whole folder with **⇧⌘O** (the sidebar becomes a
      file browser you can search).
    - Your changes **auto-save**. Switch themes from the **Themes** menu.
    - **⌘/** toggles source mode · **⌘F** find · **⌥⌘F** replace · **⌘1–6** headings.

    ## Live editing

    You get the whole Markdown vocabulary — **bold**, *italic*, `code`,
    [links](https://github.com/ourostack/ouro-md), tables, task lists, and math:

    - [x] Render Markdown beautifully
    - [ ] Try a different theme

    $$
    e^{i\\pi} + 1 = 0
    $$

    ### It stays in sync

    Open a file that another tool (or an agent) is editing, and Ouro MD updates
    live — no relaunch. Leave a note, and it's saved for them to pick up.

    ---

    Settings live under **Ouro MD ▸ Settings** (⌘,). Happy writing.
    """
}
