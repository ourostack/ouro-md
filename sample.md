# Welcome to ouro-md

A minimalist, themable, **native macOS** Markdown editor — write on the left of
your mind, read on the right. This document is here so you can *feel* the themes.

## Why it feels calm

ouro-md keeps the chrome out of your way. There's no toolbar shouting at you —
just your words, set in careful typography, on a centered page.

> Good tools disappear. You should notice the writing, not the window.

## Everything Markdown

You get the whole vocabulary:

- **Bold**, *italic*, ~~strikethrough~~, and `inline code`
- [Links](https://github.com/ourostack/ouro-md) that open in your browser
- Task lists:
  - [X]  Render Markdown beautifully
  - [X]  Switch themes live
  - [ ]  Win a design award

1. Ordered lists
2. ...with real numbers
3. ...and tidy spacing

### Code, with breathing room

```swift
struct Idea {
    let spark: String
    func realize() -> Document { Document(parsing: spark) }
}
```

### Tables line up


| Theme      | Mood             | Type  |
| :--------- | :--------------- | :---- |
| Quartz     | calm daylight    | sans  |
| Graphite   | focused night    | sans  |
| Manuscript | warm, literary   | serif |
| Newsprint  | crisp, editorial | serif |

### Math, when you need it

Inline like $e^{i\pi} + 1 = 0$, or set apart:

$$
\int_{-\infty}^{\infty} e^{-x^2}\,dx = \sqrt{\pi}
$$

---

Switch themes from **View ▸ Theme**. Drop your own `.css` in
`~/Library/Application Support/ouro-md/Themes/` to make it yours.
