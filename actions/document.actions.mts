// What Ouro MD does with a document, declared once. `scripts/generate-actions.sh` writes every door from this file:
// the App Intents and SwiftUI buttons (Sources/OuroMD/Generated/OuroActions.swift) and the MCP tools
// (Sources/OuroMD/Generated/mcp.json), and CI fails when either drifts. The menu commands call the same handlers
// (Sources/OuroMD/DocumentActionHandlers.swift). Never edit what is generated; change this file and run the script.
import { defineAction, defineActions, field } from "../tools/ouro-actions/ouro-actions.mts";

const document = (description: string, optional: boolean) =>
  field.string({
    label: "Document",
    description,
    entity: "MarkdownDocumentEntity",
    optional,
    ask: "Which document?",
  });

export const listDocuments = defineAction({
  id: "list_documents",
  consent: "read",
  label: "List Documents",
  description: "See the Markdown documents Ouro MD can reach.",
  agent: "Lists the Markdown documents in the folders Ouro MD serves, with name, folder, path and when each was modified. Changes nothing.",
  input: {
    query: field.string({ label: "Search", description: "Words to match against names and folders; leave it out to list everything.", optional: true }),
  },
  output: {
    documents: field.string({ label: "Documents", description: "One line per document: its name, two spaces, then its path. Empty when none match.", returned: true }),
    count: field.integer({ label: "Count", description: "How many documents match.", min: 0 }),
  },
  cli: "list",
});

export const readDocument = defineAction({
  id: "read_document",
  consent: "read",
  label: "Get Markdown Document",
  description: "Get the Markdown of a document, including unsaved edits.",
  agent: "Returns a document's Markdown as saved, 20000 characters at a time; a longer document says where the next page starts. Changes nothing.",
  input: {
    document: document("The document: its name as list_documents shows it (\"Plan\"), or its path, absolute or relative to a served folder. Leave it out for the document on screen.", true),
    from: field.integer({ label: "From", description: "The character (counted as a person sees letters) to start at, for the next page of a long document; 0 when left out.", optional: true, min: 0, protocolOnly: true }),
  },
  output: {
    markdown: field.string({ label: "Markdown", description: "The document's Markdown, or the page that starts at from.", returned: true }),
    name: field.string({ label: "Name", description: "The document's name." }),
    path: field.string({ label: "Path", description: "The document's path." }),
    length: field.integer({ label: "Length", description: "The whole document's length in characters.", min: 0 }),
    next: field.integer({ label: "Next", description: "Where the next page starts; absent when this page is the end.", optional: true, min: 0 }),
  },
  cli: "read",
});

export const appendToDocument = defineAction({
  id: "append_to_document",
  consent: "write",
  label: "Add to Markdown Document",
  description: "Add Markdown to the end of a document, as one undoable edit.",
  agent: "Adds Markdown to the end of a document as a new paragraph and saves it; an open Ouro MD window picks up the change. It changes only this file. Returns the outcome, checked by reading the document back.",
  input: {
    markdown: field.string({ label: "Markdown", description: "The Markdown to add, such as \"- [ ] Call the harbor master\"." }),
    document: document("The document: its name as list_documents shows it, or its path. Leave it out for the document on screen.", true),
  },
  output: {
    state: field.string({ label: "State", description: "done, or uncertain when the text read back differs beyond Markdown formatting." }),
    summary: field.string({ label: "Summary", description: "What happened, in a sentence." }),
    checked: field.string({ label: "Checked", description: "How the result was checked: the document was read back after the edit." }),
    next: field.string({ label: "Next", description: "The call to make next, when the outcome is uncertain.", optional: true }),
  },
  cli: "append",
});

export const replaceDocument = defineAction({
  id: "replace_document",
  consent: "consequential",
  label: "Replace Markdown Document",
  description: "Replace a document's whole Markdown, as one undoable edit, after you confirm.",
  agent: "Replaces a document's whole Markdown. It overwrites every line, so it asks first: without confirmed: true it changes nothing and says what to ask the person. Send confirmed: true only after the person has said yes.",
  input: {
    markdown: field.string({ label: "Markdown", description: "The Markdown that becomes the document's whole text." }),
    // Required, unlike the other actions: a person who confirms replacing a document confirms that document, even if
    // another window comes forward while they answer.
    document: document("The document: its name as list_documents shows it (\"Plan\"), or its path, absolute or relative to a served folder.", false),
    confirmed: field.boolean({ label: "Confirmed", description: "true once the person has confirmed replacing this document; leave it out to ask.", optional: true, protocolOnly: true }),
  },
  output: {
    state: field.string({ label: "State", description: "done, uncertain when the text read back differs beyond Markdown formatting, or needs-human until the person confirms." }),
    summary: field.string({ label: "Summary", description: "What happened, or what to ask the person, in a sentence." }),
    checked: field.string({ label: "Checked", description: "How the result was checked.", optional: true }),
    next: field.string({ label: "Next", description: "The call to make once the person has said yes, or after an uncertain edit.", optional: true }),
  },
  cli: "replace",
});

export const openDocument = defineAction({
  id: "open_document",
  consent: "write",
  label: "Open Markdown Document",
  description: "Open a Markdown document in Ouro MD.",
  agent: "Opens a Markdown document in Ouro MD, so the person sees it. Changes no text.",
  input: {
    document: document("The Markdown document to open, by name or path.", false),
  },
  output: {
    summary: field.string({ label: "Summary", description: "What happened, in a sentence." }),
  },
  opensApp: true,
  cli: "open",
});

export default defineActions("document", [listDocuments, readDocument, appendToDocument, replaceDocument, openDocument], { tool: "ouro-md" });
