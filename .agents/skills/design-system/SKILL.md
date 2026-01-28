---
name: design-system
description: Micelio's GitHub Primer-inspired design system. Use when creating or modifying UI components, styling pages, or ensuring design consistency.
---

# Micelio Design System

A GitHub Primer-inspired design system for consistent, accessible UI.

## Core Principles

1. **Clarity over decoration** - Minimal visual noise, clear hierarchy
2. **Consistency** - Reuse patterns and components across pages
3. **Accessibility** - Sufficient contrast, focus states, semantic HTML
4. **Dark mode support** - All colors work in both light and dark themes

## Design Tokens

All tokens are in `assets/css/theme/tokens.css` with naming: `--theme-ui-<category>-<value>`

### Colors

| Variable | Light | Dark | Usage |
|----------|-------|------|-------|
| `--theme-ui-colors-text` | #1f2328 | #f0f6fc | Primary text |
| `--theme-ui-colors-background` | #ffffff | #0d1117 | Page background |
| `--theme-ui-colors-primary` | #0969da | #4493f8 | Links, accents |
| `--theme-ui-colors-muted` | #59636e | #9198a1 | Secondary text |
| `--theme-ui-colors-border` | #d1d9e0 | #3d444d | Borders |
| `--theme-ui-colors-surface` | #f6f8fa | #151b23 | Cards, navbar |
| `--theme-ui-colors-danger` | #d1242f | #f85149 | Errors |
| `--theme-ui-colors-success` | #1a7f37 | #3fb950 | Success |

### Typography

| Element | Size | Weight |
|---------|------|--------|
| h1 | 24px | 600 |
| h2 | 20px | 600 |
| h3 | 16px | 600 |
| body | 14px | 400 |
| small | 12px | 400 |

Font: `-apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif`

### Spacing (8px grid)

| Variable | Value |
|----------|-------|
| `--theme-ui-space-0` | 4px |
| `--theme-ui-space-1` | 8px |
| `--theme-ui-space-2` | 16px |
| `--theme-ui-space-3` | 24px |
| `--theme-ui-space-4` | 32px |

### Border Radii

| Variable | Value |
|----------|-------|
| `--theme-ui-radii-small` | 3px |
| `--theme-ui-radii-default` | 6px |
| `--theme-ui-radii-large` | 12px |

## Component Patterns

### Buttons

```css
/* Primary (green) - main actions */
.project-button {
  padding: 5px 16px;
  line-height: 20px;
  background-color: var(--theme-ui-colors-button-primary-bg);
  color: var(--theme-ui-colors-button-primary-fg);
  border-radius: var(--theme-ui-radii-default);
}

/* Secondary (gray) - cancel, alternate actions */
.project-button-secondary {
  background-color: var(--theme-ui-colors-button-default-bg);
  color: var(--theme-ui-colors-button-default-fg);
  border: 1px solid var(--theme-ui-colors-button-default-border);
}
```

### Inputs

```css
.project-input {
  padding: 5px 12px;
  line-height: 20px;
  background-color: var(--theme-ui-colors-control-bg);
  border: 1px solid var(--theme-ui-colors-control-border);
  border-radius: var(--theme-ui-radii-default);
}

.project-input:focus {
  border-color: var(--theme-ui-colors-primary);
  box-shadow: 0 0 0 3px rgba(9, 105, 218, 0.3);
}
```

### Cards

```css
.card {
  padding: var(--theme-ui-space-2);
  background-color: var(--theme-ui-colors-background);
  border: var(--theme-ui-borders-thin);
  border-radius: var(--theme-ui-radii-default);
}

.card:hover {
  border-color: var(--theme-ui-colors-primary);
}
```

## File Organization

```
assets/css/
├── theme/tokens.css      # Design tokens and base styles
├── components/           # Shared component styles
├── routes/               # Page-specific styles
│   ├── navbar.css
│   ├── auth.css
│   ├── projects.css
│   └── <page>.css
└── app.css               # Import all stylesheets
```

## Best Practices

1. **Reuse existing classes** - Use `.project-button`, `.project-input` before creating new ones
2. **Use tokens** - Never hardcode colors, spacing, or sizes
3. **Test both themes** - Verify light AND dark mode
4. **Focus states** - Every interactive element needs visible focus styling
5. **Mobile-first** - Base styles first, then `@media` for larger screens
6. **Semantic names** - `.project-card` not `.blue-box`

## Creating New Pages

1. Create `assets/css/routes/<page>.css`
2. Import in `assets/css/app.css`
3. Use existing component classes first
4. Follow naming: `.<page>-<element>` (e.g., `.import-repo-list`)
