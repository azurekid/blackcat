# GitHub Copilot Instructions: AzureHacking Articles

Use this checklist in the **prompt** you send to GitHub Copilot (Chat or inline) whenever you ask it to draft a new blog post. Copy the sections below directly into your request so the model aligns with our SEO, accessibility, and publishing standards.

---

## Prompt Preface (paste into Copilot)

```
You are helping me draft a new AzureHacking research article. Follow every rule below.
1. Target keyword: <PRIMARY KEYWORD> (include exact phrase in the first 100 words)
2. Supporting keywords: <SUPPORTING KEYWORD 1>, <SUPPORTING KEYWORD 2>
3. Audience + CTA focus: <TARGET AUDIENCE NOTES + DESIRED CTA>
4. Cite authoritative sources (Microsoft docs, MITRE, CVE, etc.) with Markdown links and add at least one external authoritative citation.
5. Include at least two internal links to existing AzureHacking posts using descriptive anchor text.
6. Output valid Markdown with:
   - Single H1 that matches the article title
   - Optional metadata blurb (MITRE ATT&CK, tactic, tool mapping)
   - Blockquote summary (1–2 sentences) containing the primary keyword
   - H2 sections for major themes and H3 subsections only when needed (no skipped heading levels)
   - "Highlights" bullet list near the top when content exceeds 1,500 words
   - Conclusion section with an explicit CTA to another AzureHacking asset
7. Provide at least one image reference (HTTPS URL) with descriptive alt text.
8. Include a KQL or PowerShell detection snippet with a short explanation immediately after the code block.
9. Format guidance: paragraphs 2–4 sentences, expand acronyms on first use, prefer unordered lists for checklists, and use tables for comparisons when helpful.
10. Label all code fences with the correct language and keep blockquotes for emphasis or warnings only.
11. Suggest an excerpt (150–160 characters) and estimated read time (rounded to nearest minute) in a final metadata block that also reiterates tags used.
12. Remind me to update posts/index.json (slug, title, date, author, tags, excerpt, image, readTime, status) and sitemap.xml after saving the draft.
```

Replace the placeholder values (`<PRIMARY KEYWORD>`, `<SUPPORTING KEYWORD 1>`, `<SUPPORTING KEYWORD 2>`) before sending the prompt.

---

## After Copilot Responds

- Verify the draft against [posts/copilot-article-guidelines.md](../posts/copilot-article-guidelines.md) (SEO targets, media, citations, and publishing steps).
- Run plagiarism/originality checks and confirm all citations are accurate.
- Check the draft against [posts/copilot-article-guidelines.md](../posts/copilot-article-guidelines.md) for structure, keyword placement, media, and code requirements.
- Ensure the suggested title stays between 55–60 characters and moves the primary keyword near the front.
- Confirm the excerpt in the metadata block is 150–160 characters and action-oriented.
- Verify at least two internal links and one external authoritative citation are present and contextually relevant.
- Make sure the detection snippet includes a one-sentence explanation immediately after the code block.
- Update posts/index.json with slug (matching filename), title, date (UTC, YYYY-MM-DD), author, 3–5 tags, excerpt, hero image URL, readTime (nearest minute), and status (draft/published).
- Place any new images under posts/images/ (or provision Blob URLs) and validate the links resolve.
- Run originality/plagiarism checks and proofread for passive voice, filler words, and repeated phrases.
- After publishing, refresh sitemap.xml if needed and request indexing in Bing Webmaster Tools and Google Search Console.