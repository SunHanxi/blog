#!/usr/bin/env bash
# build.sh —— Cloudflare Workers 构建入口
#
# 做两件事:
#   1. 给 content/post 下「完全没有 front matter」的 md 自动补全 title/date/draft 等。
#      已有 front matter 的文件原样不动,绝不覆盖。
#   2. 调用 hugo 构建站点。
#
# 说明:原 Cloudflare 命令是 `hugo -D .`,其中 -D = --buildDrafts(连草稿一起构建)。
#      本仓库没有任何 draft:true 的文章,故去掉 -D 不影响结果,语义更清晰。
#      若以后确实需要发布草稿,把下方 `hugo --minify` 改回 `hugo -D --minify` 即可。


cd "$(dirname "$0")"

# ────────────────────────────────────────────────────────────────────────────
# 1. 自动补全 front matter
# ────────────────────────────────────────────────────────────────────────────
# 仅处理 content/post 下的 .md;开头第一行不是 `---` 的视为缺失 front matter。
# 已有 front matter 的文件原样不动,绝不覆盖。
# title 由文件名生成:去掉扩展名,把 _/-/. 换成空格并 trim。
now="$(date +%Y-%m-%dT%H:%M:%S+08:00)"
count=0

add_front_matter() {
    local file="$1"
    local fname
    fname="$(basename "$file" .md)"

    # 文件名 → 标题:分隔符转空格、去除首尾空格、合并多余空格
    local title
    title="$(printf '%s' "$fname" \
        | sed -e 's/[_\-\.]/ /g' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | tr -s ' ')"

    # 在文件最前面插入 front matter
    {
        printf -- '---\n'
        printf 'title: "%s"\n' "$title"
        printf 'date: %s\n' "$now"
        printf 'draft: false\n'
        printf -- '---\n\n'
        cat "$file"
    } > "$file.tmp" && mv "$file.tmp" "$file"

    echo "[build.sh] 补全 front matter: $file  (title=\"$title\")"
}

while IFS= read -r f; do
    # 跳过空文件
    [ -s "$f" ] || continue
    # 开头第一行是否为 `---`(允许有 BOM/空白行时取实际第一行判断)
    if ! head -n 1 "$f" | grep -q '^---[[:space:]]*$'; then
        add_front_matter "$f"
        count=$((count + 1))
    fi
done < <(find content/post -type f -name '*.md')

if [ "$count" -gt 0 ]; then
    echo "[build.sh] 共补全 $count 篇文章。"
else
    echo "[build.sh] 没有缺失 front matter 的文章,跳过。"
fi

# ────────────────────────────────────────────────────────────────────────────
# 2. 构建
# ────────────────────────────────────────────────────────────────────────────
echo "[build.sh] 开始 hugo 构建..."
hugo --minify
