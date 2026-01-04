#!/usr/bin/env bash

# ===== 設定 =====
DB_HOST="localhost"
DB_NAME="net_speed"
DB_USER="netmon"
LOG_FILE="$HOME/net_speed/speed_log/speedtest_agent.log"

# ★ あなたの環境に合わせて変更
WIFI_IF="wlp2s0"
WIRED_IF="enp0s31f6"
# =================


run_one() {
  local link_type="$1"  # wifi / wired
  local iface="$2"      # 例: wlp2s0, enp0s31f6

  echo "[$(date)] --- ${link_type} test start (iface=${iface}) ---"

  # IFが存在しない / upでない場合はスキップ
  if [ ! -e "/sys/class/net/${iface}" ]; then
    echo "skip: interface not found: ${iface}"
    return 0
  fi

  local state
  state="$(cat "/sys/class/net/${iface}/operstate" 2>/dev/null || true)"
  if [ "$state" != "up" ]; then
    echo "skip: interface not up: ${iface} (operstate=${state})"
    return 0
  fi

  # NICを固定して speedtest 実行（Wi-Fi/有線で分ける要）
  RESULT_JSON=$(speedtest --accept-license --accept-gdpr --format=json --interface="${iface}" 2>&1)
  RET=$?
  if [ $RET -ne 0 ]; then
    echo "speedtest failed (exit code=$RET)"
    echo "output: $RESULT_JSON"
    return 1
  fi

  # JSON から値を抜き出す（bytes/sec）
  DOWN_BW_BYTES=$(echo "$RESULT_JSON" | jq -r '.download.bandwidth // empty')
  UP_BW_BYTES=$(echo "$RESULT_JSON"   | jq -r '.upload.bandwidth // empty')
  PING_MS=$(echo "$RESULT_JSON"       | jq -r '.ping.latency // .ping // empty')

  if [ -z "$DOWN_BW_BYTES" ] || [ -z "$UP_BW_BYTES" ] || [ -z "$PING_MS" ]; then
    echo "Failed to parse speedtest json"
    echo "json: $RESULT_JSON"
    return 1
  fi

  # bytes/sec → bits/sec → Mbps（小数第2位まで）
  DOWN_MBPS=$(awk "BEGIN {printf \"%.2f\", $DOWN_BW_BYTES*8/1000000}")
  UP_MBPS=$(awk "BEGIN {printf \"%.2f\", $UP_BW_BYTES*8/1000000}")

  echo "Download: ${DOWN_MBPS} Mbps, Upload: ${UP_MBPS} Mbps, Ping: ${PING_MS} ms"

  # INSERT（link_type/iface/hostを追加）
  psql -h "$DB_HOST" -U "$DB_USER" -d "$DB_NAME" <<EOF
INSERT INTO speedtest_logs
  (measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host)
VALUES
  (NOW(), $DOWN_MBPS, $UP_MBPS, $PING_MS, '${link_type}', '${iface}', '${HOSTNAME_STR}');
EOF

  if [ $? -ne 0 ]; then
    echo "Failed to insert into PostgreSQL"
    return 1
  fi

  echo "[$(date)] --- ${link_type} test end ---"
  echo
}

{
  echo "[$(date)] ===== start dual speedtest ====="
  run_one "wireless"  "$WIFI_IF"
  run_one "wired" "$WIRED_IF"
  echo "[$(date)] ===== end dual speedtest ====="
  echo
} >> "$LOG_FILE" 2>&1
