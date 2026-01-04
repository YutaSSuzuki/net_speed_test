#!/usr/bin/env bash

# ===== 設定 =====
DB_HOST="localhost"
DB_NAME="net_speed"
DB_USER="netmon"                     # さっき作った監視用ユーザー
LOG_FILE="$HOME/net_speed/speed_log/speedtest_agent.log" # ユーザーのホームにログを出す
# =================

{
  echo "[$(date)] ----- start speedtest -----"

  # speedtest をライセンス同意付き & JSON形式で実行
  RESULT_JSON=$(speedtest --format=json 2>&1)
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "speedtest failed (exit code=$RET)"
    echo "output: $RESULT_JSON"
    exit 1
  fi

  # JSON から値を抜き出す（bytes/sec）
  DOWN_BW_BYTES=$(echo "$RESULT_JSON" | jq '.download.bandwidth'| tail -n 1)
  UP_BW_BYTES=$(echo "$RESULT_JSON" | jq '.upload.bandwidth'| tail -n 1)
  PING_MS=$(echo "$RESULT_JSON" | jq '.ping.latency'| tail -n 1)

  if [ -z "$DOWN_BW_BYTES" ] || [ "$DOWN_BW_BYTES" = "null" ]; then
    echo "Failed to parse download.bandwidth"
    exit 1
  fi

  # bytes/sec → bits/sec → Mbps（小数第2位まで）
  DOWN_MBPS=$(awk "BEGIN {printf \"%.2f\", $DOWN_BW_BYTES*8/1000000}")
  UP_MBPS=$(awk "BEGIN {printf \"%.2f\", $UP_BW_BYTES*8/1000000}")

  echo "Download: ${DOWN_MBPS} Mbps, Upload: ${UP_MBPS} Mbps, Ping: ${PING_MS} ms"

  # ログインユーザーの .pgpass を使って psql で INSERT
  #   ~/.pgpass に
  #     localhost:5432:net_speed:netmon:パスワード
  #   を書いて chmod 600 ~/.pgpass しておくこと
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" <<EOF
INSERT INTO speedtest_logs (measured_at, download_mbps, upload_mbps, ping_ms)
VALUES (NOW(), $DOWN_MBPS, $UP_MBPS, $PING_MS);
EOF

  if [ $? -ne 0 ]; then
    echo "Failed to insert into PostgreSQL"
    exit 1
  fi

  echo "[$(date)] ----- end speedtest -----"
  echo
} >> "$LOG_FILE" 2>&1
