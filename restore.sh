#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

WORK=/root/salon-restore
ask() { local v; read -r -p "$1" v </dev/tty; printf '%s' "$v"; }

[[ $EUID -eq 0 ]] || { echo "root で実行してください（sudo -i のあとにもう一度）"; exit 1; }

echo "サーバーの復元を始めます。"
echo
apt-get update -q >/dev/null
DEBIAN_FRONTEND=noninteractive apt-get install -y -q age curl ca-certificates tar >/dev/null

mkdir -p "$WORK"
FILE="$WORK/backup.tar.age"

echo "【1】バックアップファイル"
echo "  Google ドライブで戻したい日の .tar.age を「リンクを知っている全員」に共有し、そのリンクを貼ってください。"
echo "  （サーバー上にファイルがある場合は、そのパスでもかまいません）"
SRC="$(ask "  > ")"
if [[ -f "$SRC" ]]; then
  cp -- "$SRC" "$FILE"
else
  ID="$(printf '%s' "$SRC" | sed -nE 's#.*/d/([A-Za-z0-9_-]+).*#\1#p; s#.*[?&]id=([A-Za-z0-9_-]+).*#\1#p' | head -1)"
  [[ -n "$ID" ]] || { echo "リンクの形が違います。"; exit 1; }
  echo "  ダウンロードしています…"
  curl -fL --retry 3 -o "$FILE" "https://drive.usercontent.google.com/download?id=$ID&export=download&confirm=t"
fi
head -c 22 "$FILE" | grep -q "age-encryption.org/v1" || { echo "暗号化されたバックアップではありません（共有の設定かリンクを確認してください）。"; exit 1; }
echo "  OK（$(du -h "$FILE" | cut -f1)）"
echo

echo "【2】バックアップの鍵"
echo "  AGE-SECRET-KEY-1 で始まる1行を貼ってください（画面には表示されません）。"
read -r -s -p "  > " KEY </dev/tty; echo
[[ "$KEY" == AGE-SECRET-KEY-1* ]] || { echo "鍵の形が違います。"; exit 1; }
KEYFILE="$(mktemp)"
printf '%s\n' "$KEY" > "$KEYFILE"
unset KEY

echo "  ほどいています…"
rm -rf "$WORK/backup"; mkdir -p "$WORK/backup"
if ! age -d -i "$KEYFILE" "$FILE" | tar -x -C "$WORK/backup"; then
  shred -u "$KEYFILE"; echo "ほどけませんでした（鍵が違う可能性があります）。"; exit 1
fi
shred -u "$KEYFILE"
DIR="$(find "$WORK/backup" -mindepth 1 -maxdepth 1 -type d | head -1)"
[[ -f "$DIR/full-restore.sh" ]] || { echo "このバックアップには自動復元の手順が入っていません（2026年10月14日より前の形式）。"; exit 1; }
echo "  OK（$(basename "$DIR")）"
echo

echo "【3】復元"
echo "  このサーバーに、バックアップの内容をすべて戻します。"
[[ "$(ask "  始めてよければ yes と入力: ")" == "yes" ]] || { echo "やめました。"; exit 1; }
bash "$DIR/full-restore.sh" "$DIR"
rm -f "$FILE"
