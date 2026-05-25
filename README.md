# CodePacker

**Right-click any project folder in macOS Finder. Get LLM-ready context. Instantly.**

Directory tree + every source file in code-fenced markdown. One right-click. The context packer for developers who build with AI.

## The Problem

To get useful output from an LLM about your codebase, you need structural context — the directory tree, how files relate, and the actual source code with syntax hints. Currently this means opening each file, copying, pasting into a markdown fence, typing the file path, and repeating for 20+ files. CodePacker reduces that to a right-click and a paste.

## Modes

| Mode | Menu Label | Output | Use Case |
|------|-----------|--------|----------|
| Clipboard | "Pack to Clipboard" | Markdown to clipboard | Paste into Claude/ChatGPT/Cursor |
| File | "Pack to File" | Saves `_packed.md` in the folder | Share with collaborators, archive |
| Compact | "Pack Compact" | Minimal markdown to clipboard | Smaller context windows |

## Install

```bash
git clone https://github.com/opera10r/CodePacker.git
cd CodePacker
./install.sh
```

The installer will open **System Settings** automatically. Toggle ON all 3 CodePacker actions under **Finder Extensions**, then press Enter to finish.

After that, right-click any folder in Finder → **Quick Actions** → pick a CodePacker mode.

## Uninstall

```bash
cd CodePacker
./uninstall.sh
```

## Features

- **Zero dependencies**: Uses only macOS built-in tools
- **Respects .gitignore**: Automatically skips ignored files and directories
- **Smart filtering**: Skips binaries, media, lock files, `node_modules`, build artifacts, and 80+ default ignore patterns
- **Syntax-tagged code fences**: 60+ language mappings (Python, JS, TS, Swift, Rust, Go, etc.)
- **Token estimation**: Notification shows approximate token count for the packed output
- **Custom ignore patterns**: Add your own patterns in `~/Library/Application Support/CodePacker/custom-ignore.txt`
- **Directory tree**: Clean ASCII tree visualization at the top of every pack

## Example Output

````markdown
# Project: my-app

## Directory Structure

```
my-app/
├── src/
│   ├── index.ts
│   └── utils.ts
├── package.json
└── tsconfig.json
```

## Source Files

### `src/index.ts`

```typescript
import { helper } from './utils';
console.log(helper('world'));
```

### `src/utils.ts`

```typescript
export function helper(name: string): string {
  return `Hello, ${name}!`;
}
```
````

## Pricing

- **Free**: 1 pack per day
- **Unlimited**: [$1/month](https://buy.stripe.com/7sY6oG62S15CciI9PU2cg05)

To activate after purchase:

```bash
codepacker activate <your_license_key>
```

Check your status anytime:

```bash
codepacker status
```

## Requirements

- macOS 13+ (Ventura or later)
- No external dependencies

## License

MIT

---

Built by Raven's Gate Publishers LLC
