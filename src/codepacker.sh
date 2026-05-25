#!/bin/zsh
# CodePacker — Right-Click Project-to-LLM Context Packer
# Right-click any folder → pack all source files into LLM-ready markdown
# Usage: codepacker.sh <mode> <folder>
# Modes: clipboard, file, compact

set -uo pipefail
setopt TYPESET_SILENT 2>/dev/null

# ─── Config ───────────────────────────────────────────────────────────────────

APP_NAME="CodePacker"
SUPPORT_DIR="$HOME/Library/Application Support/CodePacker"
USAGE_FILE="$SUPPORT_DIR/usage"
DAILY_LIMIT=1
LICENSE_FILE="$SUPPORT_DIR/license"
LICENSE_KEY_FILE="$SUPPORT_DIR/license_key"
API_URL="https://codepacker-worker.opera10r.workers.dev"
LOG_FILE="$SUPPORT_DIR/debug.log"

MAX_FILE_SIZE=524288        # 512 KB per file
CHARS_PER_TOKEN=4           # ~4 chars per token for code

# ─── Setup ────────────────────────────────────────────────────────────────────

mkdir -p "$SUPPORT_DIR"

# ─── Logging ──────────────────────────────────────────────────────────────────

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE" 2>/dev/null
}

# ─── Notification ─────────────────────────────────────────────────────────────

notify() {
    local title="$1"
    local body="$2"
    body="${body//\\/\\\\}"
    body="${body//\"/\\\"}"
    osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null &
}

# ─── Usage Tracking ──────────────────────────────────────────────────────────

check_usage() {
    if [[ -f "$LICENSE_FILE" ]] && [[ "$(cat "$LICENSE_FILE" 2>/dev/null)" == "active" ]]; then
        return 0
    fi

    local today
    today=$(date +%Y-%m-%d)

    if [[ -f "$USAGE_FILE" ]]; then
        local stored_date stored_count
        stored_date=$(cut -d: -f1 "$USAGE_FILE")
        stored_count=$(cut -d: -f2 "$USAGE_FILE")

        if [[ "$stored_date" == "$today" ]] && (( stored_count >= DAILY_LIMIT )); then
            notify "$APP_NAME" "Daily free pack used. Unlimited for \$1/month."
            exit 0
        fi
    fi
}

increment_usage() {
    if [[ -f "$LICENSE_FILE" ]] && [[ "$(cat "$LICENSE_FILE" 2>/dev/null)" == "active" ]]; then
        return 0
    fi

    local today
    today=$(date +%Y-%m-%d)

    if [[ -f "$USAGE_FILE" ]]; then
        local stored_date stored_count
        stored_date=$(cut -d: -f1 "$USAGE_FILE")
        stored_count=$(cut -d: -f2 "$USAGE_FILE")

        if [[ "$stored_date" == "$today" ]]; then
            echo "$today:$((stored_count + 1))" > "$USAGE_FILE"
        else
            echo "$today:1" > "$USAGE_FILE"
        fi
    else
        echo "$today:1" > "$USAGE_FILE"
    fi
}

# ─── Validation ───────────────────────────────────────────────────────────────

validate_folder() {
    local folder="$1"
    if [[ ! -d "$folder" ]]; then
        notify "$APP_NAME" "Not a folder: $(basename "$folder")"
        log "ERROR: Not a folder: $folder"
        exit 1
    fi
}

# ─── Default Ignore Patterns ─────────────────────────────────────────────────

DEFAULT_IGNORES=(
    # Version control
    .git .svn .hg .gitmodules
    # Dependencies
    node_modules vendor .bundle Pods Carthage .npm .yarn bower_components
    __pycache__ .venv venv env .env pip-wheel-metadata .eggs
    # Build artifacts
    build dist out .next .nuxt .output .vercel .netlify target
    # IDE
    .idea .vscode .DS_Store Thumbs.db
    # Lock files
    package-lock.json yarn.lock pnpm-lock.yaml Gemfile.lock
    Pipfile.lock poetry.lock composer.lock Cargo.lock
    # Coverage & test artifacts
    coverage .nyc_output htmlcov .coverage .pytest_cache .tox
    # Logs
    logs
    # Misc
    .terraform .cache .parcel-cache .turbo
)

# File extension patterns to ignore (binary/media)
BINARY_EXTENSIONS=(
    png jpg jpeg gif webp ico svg
    mp3 mp4 wav flac ogg avi mov mkv
    pdf zip tar gz tgz rar 7z bz2 dmg iso
    exe dll woff woff2 ttf eot otf
    o a so dylib class jar war
    pyc pyo swp swo
)

# ─── Ignore Logic ─────────────────────────────────────────────────────────────

load_ignore_patterns() {
    local folder="$1"

    # Start with defaults
    IGNORE_DIRS=("${DEFAULT_IGNORES[@]}")
    IGNORE_FILE_PATTERNS=()

    # Parse .gitignore if present
    local gitignore="$folder/.gitignore"
    if [[ -f "$gitignore" ]]; then
        while IFS= read -r line; do
            line="${line%%#*}"       # Strip comments
            line="${line## }"        # Trim leading space
            line="${line%% }"        # Trim trailing space
            line="${line%/}"         # Strip trailing slash
            [[ -z "$line" ]] && continue
            [[ "$line" == "!"* ]] && continue  # Skip negation patterns (complex)
            IGNORE_DIRS+=("$line")
        done < "$gitignore"
    fi

    # Parse custom-ignore if present
    local custom="$SUPPORT_DIR/custom-ignore.txt"
    if [[ -f "$custom" ]]; then
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line## }"
            line="${line%% }"
            line="${line%/}"
            [[ -z "$line" ]] && continue
            IGNORE_DIRS+=("$line")
        done < "$custom"
    fi
}

should_ignore_dir() {
    local dirname="$1"
    local pattern
    for pattern in "${IGNORE_DIRS[@]}"; do
        [[ "$dirname" == $~pattern ]] && return 0
    done
    return 1
}

should_ignore_file() {
    local filename="$1"
    local ext="${filename##*.}"
    ext="${ext:l}"  # lowercase

    # Check binary extensions
    local bext
    for bext in "${BINARY_EXTENSIONS[@]}"; do
        [[ "$ext" == "$bext" ]] && return 0
    done

    # Check ignore patterns from .gitignore
    local pattern
    for pattern in "${IGNORE_DIRS[@]}"; do
        [[ "$filename" == $~pattern ]] && return 0
    done

    return 1
}

is_binary() {
    local file="$1"
    # Quick check: if file contains null bytes in first 8KB, it's binary
    local chunk
    chunk=$(head -c 8192 "$file" 2>/dev/null | tr -d '[:print:][:space:]' | head -c 1)
    # Actually use file command - more reliable
    local filetype
    filetype=$(file -b --mime-type "$file" 2>/dev/null)
    [[ "$filetype" != text/* ]] && [[ "$filetype" != application/json ]] && [[ "$filetype" != application/xml ]] && [[ "$filetype" != application/javascript ]] && return 0
    return 1
}

# ─── Language Mapping ─────────────────────────────────────────────────────────

get_language_tag() {
    local filename="$1"
    local basename="${filename##*/}"
    local ext="${filename##*.}"
    ext="${ext:l}"

    # Special filenames first
    case "$basename" in
        Makefile)       echo "makefile" ;;
        Dockerfile)     echo "dockerfile" ;;
        Jenkinsfile)    echo "groovy" ;;
        Vagrantfile|Rakefile|Gemfile|Brewfile) echo "ruby" ;;
        Procfile)       echo "yaml" ;;
        .gitignore|.dockerignore) echo "gitignore" ;;
        .editorconfig)  echo "ini" ;;
        Pipfile|Cargo.toml|pyproject.toml) echo "toml" ;;
        tsconfig.json|jsconfig.json) echo "jsonc" ;;
        CLAUDE.md)      echo "markdown" ;;
        *)
            # Extension mapping
            case "$ext" in
                py|pyx|pyi)         echo "python" ;;
                js|mjs|cjs)         echo "javascript" ;;
                jsx)                echo "jsx" ;;
                ts)                 echo "typescript" ;;
                tsx)                echo "tsx" ;;
                html|htm)           echo "html" ;;
                css)                echo "css" ;;
                scss)               echo "scss" ;;
                sass)               echo "sass" ;;
                less)               echo "less" ;;
                vue)                echo "vue" ;;
                svelte)             echo "svelte" ;;
                swift)              echo "swift" ;;
                kt|kts)             echo "kotlin" ;;
                java)               echo "java" ;;
                scala)              echo "scala" ;;
                c|h)                echo "c" ;;
                cpp|hpp|cc|cxx)     echo "cpp" ;;
                cs)                 echo "csharp" ;;
                go)                 echo "go" ;;
                rs)                 echo "rust" ;;
                rb)                 echo "ruby" ;;
                php)                echo "php" ;;
                lua)                echo "lua" ;;
                r)                  echo "r" ;;
                m|mm)               echo "objectivec" ;;
                dart)               echo "dart" ;;
                ex|exs)             echo "elixir" ;;
                erl)                echo "erlang" ;;
                hs)                 echo "haskell" ;;
                clj)                echo "clojure" ;;
                lisp)               echo "lisp" ;;
                pl|pm)              echo "perl" ;;
                sh|bash)            echo "bash" ;;
                zsh)                echo "zsh" ;;
                fish)               echo "fish" ;;
                ps1)                echo "powershell" ;;
                bat|cmd)            echo "batch" ;;
                json)               echo "json" ;;
                jsonc)              echo "jsonc" ;;
                yaml|yml)           echo "yaml" ;;
                toml)               echo "toml" ;;
                ini|cfg)            echo "ini" ;;
                conf)               echo "conf" ;;
                xml|plist)          echo "xml" ;;
                graphql|gql)        echo "graphql" ;;
                proto)              echo "protobuf" ;;
                md|mdx)             echo "markdown" ;;
                rst)                echo "rst" ;;
                tex)                echo "latex" ;;
                txt)                echo "text" ;;
                sql)                echo "sql" ;;
                prisma)             echo "prisma" ;;
                tf|hcl)             echo "hcl" ;;
                dockerfile)         echo "dockerfile" ;;
                cmake)              echo "cmake" ;;
                gradle)             echo "gradle" ;;
                env|env.*)          echo "dotenv" ;;
                *)                  echo "" ;;
            esac
            ;;
    esac
}

# ─── Directory Tree Generator ─────────────────────────────────────────────────

generate_tree() {
    local dir="$1"
    local prefix="${2:-}"
    local entries=()
    local entry basename fsize

    # Collect all entries (files + dirs), skip . and ..
    for entry in "$dir"/*(N) "$dir"/.*(N); do
        basename="${entry##*/}"
        [[ "$basename" == "." || "$basename" == ".." ]] && continue
        should_ignore_dir "$basename" && continue
        if [[ -f "$entry" ]]; then
            should_ignore_file "$basename" && continue
            fsize=$(stat -f%z "$entry" 2>/dev/null || echo "0")
            (( fsize > MAX_FILE_SIZE )) && continue
            is_binary "$entry" && continue
        fi
        entries+=("$entry")
    done

    local count=${#entries[@]}
    local i=0
    for entry in "${entries[@]}"; do
        i=$((i + 1))
        basename="${entry##*/}"
        local connector="├── "
        local extension="│   "
        if (( i == count )); then
            connector="└── "
            extension="    "
        fi

        if [[ -d "$entry" ]]; then
            printf '%s\n' "${prefix}${connector}${basename}/"
            generate_tree "$entry" "${prefix}${extension}"
        else
            printf '%s\n' "${prefix}${connector}${basename}"
        fi
    done
}

# ─── Core Packing Engine ─────────────────────────────────────────────────────

pack_directory() {
    local dir="$1"
    local compact="${2:-false}"
    local dirname="${dir##*/}"

    load_ignore_patterns "$dir"

    # Header
    printf '%s\n' "# Project: $dirname"
    printf '%s\n' ""
    printf '%s\n' "## Directory Structure"
    printf '%s\n' ""
    printf '%s\n' '```'
    printf '%s\n' "$dirname/"
    generate_tree "$dir" ""
    printf '%s\n' '```'
    printf '%s\n' ""
    printf '%s\n' "## Source Files"

    # Walk and pack files
    pack_files_recursive "$dir" "$dir" "$compact"
}

pack_files_recursive() {
    local dir="$1"
    local root="$2"
    local compact="$3"
    local entry basename fsize relpath lang

    for entry in "$dir"/*(N) "$dir"/.*(N); do
        [[ ! -e "$entry" ]] && continue
        basename="${entry##*/}"
        [[ "$basename" == "." || "$basename" == ".." ]] && continue
        should_ignore_dir "$basename" && continue

        if [[ -d "$entry" ]]; then
            pack_files_recursive "$entry" "$root" "$compact"
        elif [[ -f "$entry" ]]; then
            should_ignore_file "$basename" && continue

            fsize=$(stat -f%z "$entry" 2>/dev/null || echo "0")
            (( fsize > MAX_FILE_SIZE )) && continue
            is_binary "$entry" && continue

            relpath="${entry#$root/}"
            lang=$(get_language_tag "$basename")

            printf '\n%s\n' "### \`$relpath\`"
            printf '\n%s\n' "\`\`\`${lang}"
            cat "$entry" 2>/dev/null
            printf '\n%s\n' '```'

            FILE_COUNT=$((FILE_COUNT + 1))
            TOTAL_CHARS=$((TOTAL_CHARS + fsize))
        fi
    done
}

# ─── Mode Handlers ────────────────────────────────────────────────────────────

mode_clipboard() {
    local folder="$1"
    local compact="${2:-false}"
    validate_folder "$folder"
    check_usage

    log "Packing: $folder (mode: clipboard, compact: $compact)"

    FILE_COUNT=0
    TOTAL_CHARS=0

    local result
    result=$(pack_directory "$folder" "$compact")
    printf '%s' "$result" | pbcopy

    TOTAL_CHARS=${#result}
    local est_tokens=$((TOTAL_CHARS / CHARS_PER_TOKEN))
    local token_str
    if (( est_tokens >= 1000 )); then
        token_str="~$((est_tokens / 1000))K tokens"
    else
        token_str="~${est_tokens} tokens"
    fi

    increment_usage
    notify "$APP_NAME" "$FILE_COUNT files ($token_str) copied to clipboard"
    log "Done: $FILE_COUNT files, $TOTAL_CHARS chars, $token_str"
}

mode_file() {
    local folder="$1"
    local compact="${2:-false}"
    validate_folder "$folder"
    check_usage

    log "Packing: $folder (mode: file, compact: $compact)"

    FILE_COUNT=0
    TOTAL_CHARS=0

    local dirname="${folder##*/}"
    local output_path="${folder}/${dirname}_packed.md"

    local result
    result=$(pack_directory "$folder" "$compact")
    printf '%s\n' "$result" > "$output_path"

    TOTAL_CHARS=${#result}
    local est_tokens=$((TOTAL_CHARS / CHARS_PER_TOKEN))
    local token_str
    if (( est_tokens >= 1000 )); then
        token_str="~$((est_tokens / 1000))K tokens"
    else
        token_str="~${est_tokens} tokens"
    fi

    increment_usage
    notify "$APP_NAME" "$FILE_COUNT files ($token_str) saved to ${dirname}_packed.md"
    log "Saved: $output_path — $FILE_COUNT files, $token_str"
}

# ─── Main ─────────────────────────────────────────────────────────────────────

if (( $# < 2 )); then
    echo "Usage: codepacker <mode> <folder>"
    echo "Modes: clipboard, file, compact"
    exit 1
fi

MODE="$1"
shift

FOLDER="$1"

case "$MODE" in
    clipboard)  mode_clipboard "$FOLDER" "false" ;;
    file)       mode_file "$FOLDER" "false" ;;
    compact)    mode_clipboard "$FOLDER" "true" ;;
    *)
        echo "Unknown mode: $MODE"
        echo "Modes: clipboard, file, compact"
        exit 1
        ;;
esac
