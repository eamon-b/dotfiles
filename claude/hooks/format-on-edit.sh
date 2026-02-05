#!/bin/bash
# Post-edit hook to format code according to ~/.claude/format-config.json
# Called by Claude Code after Edit tool completes

set -euo pipefail

# Ensure common tool paths are available
export PATH="$HOME/.local/bin:$HOME/.nvm/versions/node/v24.13.0/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

CONFIG_FILE="$HOME/.claude/format-config.json"
LOG_FILE="$HOME/.claude/debug/format-hook.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Read file path from stdin (Claude Code passes hook data as JSON via stdin)
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.file_path // .filePath // empty' 2>/dev/null)

# Fallback: check if passed as argument
if [[ -z "$FILE_PATH" && $# -gt 0 ]]; then
    FILE_PATH="$1"
fi

if [[ -z "$FILE_PATH" || ! -f "$FILE_PATH" ]]; then
    log "No valid file path provided or file doesn't exist: $FILE_PATH"
    exit 0
fi

# Early exit for unsupported file types (avoids unnecessary config parsing)
# Add new extensions here as formatters are added
SUPPORTED_EXTENSIONS="py|pyi|js|jsx|ts|tsx|mjs|cjs|json|jsonc"
EXT_CHECK="${FILE_PATH##*.}"
if [[ ! "$EXT_CHECK" =~ ^($SUPPORTED_EXTENSIONS)$ ]]; then
    exit 0
fi

log "Processing: $FILE_PATH"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    log "Config file not found: $CONFIG_FILE"
    exit 0
fi

# Check if formatting is enabled globally
ENABLED=$(jq -r '.enabled // true' "$CONFIG_FILE")
if [[ "$ENABLED" != "true" ]]; then
    log "Formatting disabled globally"
    exit 0
fi

# Get file extension
EXT=".${FILE_PATH##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

# Determine which formatter to use based on extension
format_javascript() {
    local file="$1"
    local config_section="javascript"

    local section_enabled=$(jq -r ".$config_section.enabled // true" "$CONFIG_FILE")
    if [[ "$section_enabled" != "true" ]]; then
        log "JavaScript formatting disabled"
        return 0
    fi

    # Build prettier options from config
    local tab_width=$(jq -r ".$config_section.options.tabWidth // 2" "$CONFIG_FILE")
    local use_tabs=$(jq -r ".$config_section.options.useTabs // false" "$CONFIG_FILE")
    local semi=$(jq -r ".$config_section.options.semi // true" "$CONFIG_FILE")
    local single_quote=$(jq -r ".$config_section.options.singleQuote // false" "$CONFIG_FILE")
    local trailing_comma=$(jq -r ".$config_section.options.trailingComma // \"es5\"" "$CONFIG_FILE")
    local print_width=$(jq -r ".$config_section.options.printWidth // 80" "$CONFIG_FILE")

    local prettier_args=(
        "--write"
        "--tab-width" "$tab_width"
        "--print-width" "$print_width"
        "--trailing-comma" "$trailing_comma"
    )

    [[ "$use_tabs" == "true" ]] && prettier_args+=("--use-tabs")
    [[ "$semi" == "false" ]] && prettier_args+=("--no-semi")
    [[ "$single_quote" == "true" ]] && prettier_args+=("--single-quote")

    # Try to find prettier
    if command -v prettier &>/dev/null; then
        log "Running: prettier ${prettier_args[*]} $file"
        prettier "${prettier_args[@]}" "$file" 2>&1 | while read -r line; do log "prettier: $line"; done
    elif command -v npx &>/dev/null; then
        log "Running: npx prettier ${prettier_args[*]} $file"
        npx --yes prettier "${prettier_args[@]}" "$file" 2>&1 | while read -r line; do log "npx prettier: $line"; done
    else
        log "ERROR: prettier not found and npx not available"
        return 1
    fi
}

format_python() {
    local file="$1"
    local config_section="python"

    local section_enabled=$(jq -r ".$config_section.enabled // true" "$CONFIG_FILE")
    if [[ "$section_enabled" != "true" ]]; then
        log "Python formatting disabled"
        return 0
    fi

    local line_length=$(jq -r ".$config_section.options.lineLength // 100" "$CONFIG_FILE")
    local indent_width=$(jq -r ".$config_section.options.indentWidth // 4" "$CONFIG_FILE")

    local ruff_args=(
        "format"
        "--line-length" "$line_length"
    )

    # Try to find ruff
    if command -v ruff &>/dev/null; then
        log "Running: ruff ${ruff_args[*]} $file"
        ruff "${ruff_args[@]}" "$file" 2>&1 | while read -r line; do log "ruff: $line"; done
    elif command -v uvx &>/dev/null; then
        log "Running: uvx ruff ${ruff_args[*]} $file"
        uvx ruff "${ruff_args[@]}" "$file" 2>&1 | while read -r line; do log "uvx ruff: $line"; done
    elif command -v pipx &>/dev/null; then
        log "Running: pipx run ruff ${ruff_args[*]} $file"
        pipx run ruff "${ruff_args[@]}" "$file" 2>&1 | while read -r line; do log "pipx ruff: $line"; done
    else
        log "ERROR: ruff not found and uvx/pipx not available"
        return 1
    fi
}

format_json() {
    local file="$1"
    local config_section="json"

    local section_enabled=$(jq -r ".$config_section.enabled // true" "$CONFIG_FILE")
    if [[ "$section_enabled" != "true" ]]; then
        log "JSON formatting disabled"
        return 0
    fi

    local tab_width=$(jq -r ".$config_section.options.tabWidth // 2" "$CONFIG_FILE")

    local prettier_args=(
        "--write"
        "--tab-width" "$tab_width"
        "--parser" "json"
    )

    if command -v prettier &>/dev/null; then
        log "Running: prettier ${prettier_args[*]} $file"
        prettier "${prettier_args[@]}" "$file" 2>&1 | while read -r line; do log "prettier: $line"; done
    elif command -v npx &>/dev/null; then
        log "Running: npx prettier ${prettier_args[*]} $file"
        npx --yes prettier "${prettier_args[@]}" "$file" 2>&1 | while read -r line; do log "npx prettier: $line"; done
    else
        log "ERROR: prettier not found for JSON formatting"
        return 1
    fi
}

# Check extensions and call appropriate formatter
JS_EXTENSIONS=$(jq -r '.javascript.extensions // [".js", ".jsx", ".ts", ".tsx", ".mjs", ".cjs"] | .[]' "$CONFIG_FILE")
PY_EXTENSIONS=$(jq -r '.python.extensions // [".py", ".pyi"] | .[]' "$CONFIG_FILE")
JSON_EXTENSIONS=$(jq -r '.json.extensions // [".json", ".jsonc"] | .[]' "$CONFIG_FILE")

if echo "$JS_EXTENSIONS" | grep -qx -- "$EXT_LOWER"; then
    format_javascript "$FILE_PATH"
elif echo "$PY_EXTENSIONS" | grep -qx -- "$EXT_LOWER"; then
    format_python "$FILE_PATH"
elif echo "$JSON_EXTENSIONS" | grep -qx -- "$EXT_LOWER"; then
    format_json "$FILE_PATH"
else
    log "No formatter configured for extension: $EXT_LOWER"
fi

log "Completed processing: $FILE_PATH"
exit 0
