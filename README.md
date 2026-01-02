# ネットワーク可視化（Speedtest + PostgreSQL + Grafana）

家庭内ネットワークの速度低下を「見える化」するための構成です。  
Speedtest（Ookla公式CLI）で定期計測し、結果を PostgreSQL に保存し、Grafana で可視化します。

- 計測: `speedtest`（Ookla公式CLI）
- 保存: PostgreSQL
- 可視化: Grafana（インストールしてDataSource追加でOK）

> ※本構成は「インターネット回線速度（ISP速度）」の計測です。宅内LANだけを測りたい場合は iperf3 構成が適します。

---

## 構成

1. 計測端末（Ubuntu）で `speedtest` を実行
2. 結果(JSON)から必要項目を抽出し、PostgreSQLへINSERT
3. Grafana が PostgreSQL を参照して時系列グラフ化

---

## 前提・要件

- Ubuntu 22.04 / 24.04（他でも概ね同様）
- PostgreSQL（例: 14+）
- Grafana（初期設定でOK）
- Ookla Speedtest CLI（`speedtest`）
- `jq`
- `psql`（PostgreSQLクライアント）

---

## セットアップ手順（計測端末）

### 必要パッケージをインストール

```bash
sudo apt update
sudo apt install -y jq postgresql postgresql-client grafana curl
```

### Speedtest（Ookla）をインストール

```bash
curl -s https://packagecloud.io/install/repositories/ookla/speedtest-cli/script.deb.sh | sudo bash
sudo apt install -y speedtest
```

動作確認（ライセンス同意が求められる場合あり）:

```bash
speedtest --version
speedtest --format=json | head
```

---

## PostgreSQL 初期設定

ここでは以下で作成します。

- DB名: `net_speed`
- DBユーザー: `netmon`

### ユーザー/DB作成

```bash
sudo -u postgres psql
```

```sql
CREATE USER netmon WITH PASSWORD 'CHANGE_ME';
CREATE DATABASE net_speed OWNER netmon;
\q
```

---

## テーブル作成（スキーマ）

`sql/schema.sql` を用意している前提（無い場合は下の例を利用）。

### スキーマ適用

```bash
psql -U netmon -d net_speed -f sql/schema.sql
```

### schema.sql（例）

```sql
CREATE TABLE IF NOT EXISTS speedtest_logs (
  id            BIGSERIAL PRIMARY KEY,
  measured_at   TIMESTAMPTZ NOT NULL DEFAULT now(),

  -- 有線/無線の区別（任意）
  link_type      TEXT NOT NULL DEFAULT 'unknown', -- wired / wifi / unknown
  interface_name TEXT,
  ssid           TEXT,

  -- 計測値（Mbps / ms）
  download_mbps DOUBLE PRECISION,
  upload_mbps   DOUBLE PRECISION,
  ping_ms       DOUBLE PRECISION,

  -- 付加情報
  server_name   TEXT,
  raw_json      JSONB
);

CREATE INDEX IF NOT EXISTS speedtest_logs_time_idx
  ON speedtest_logs (measured_at);

CREATE INDEX IF NOT EXISTS speedtest_logs_link_time_idx
  ON speedtest_logs (link_type, measured_at);
```

---

## 計測スクリプト設定

リポジトリの `speedtest_to_pg.sh` を使用します。

### 実行権限付与

```bash
chmod +x ./speedtest_to_pg.sh
```

### 環境変数ファイル（.env）を作成（推奨）

> `.env` は秘密情報（パスワード等）を含むため **Gitにコミットしない** でください。

```bash
cat > .env <<'EOF'
DB_HOST=localhost
DB_NAME=net_speed
DB_USER=netmon
DB_PASS=CHANGE_ME

# 任意：有線/無線の識別情報
LINK_TYPE=wifi
IFACE_NAME=wlan0
SSID=home_wifi
EOF
```

`.gitignore` に追加:

```bash
echo ".env" >> .gitignore
```

### 手動実行で動作確認

```bash
set -a
source .env
set +a

./speedtest_to_pg.sh
```

DBに入ったか確認:

```bash
psql -U netmon -d net_speed -c \
"SELECT measured_at, link_type, download_mbps, upload_mbps, ping_ms FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
```

---

## 定期実行（systemd timer 推奨）

`systemd/` に `net-speed.service` と `net-speed.timer` を置く想定です。

### systemd設定を配置

```bash
sudo cp systemd/net-speed.service systemd/net-speed.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now net-speed.timer
```

状態確認:

```bash
systemctl status net-speed.timer --no-pager
journalctl -u net-speed.service -n 50 --no-pager
```

### systemd設定例

`systemd/net-speed.service`

```ini
[Unit]
Description=Network speed measurement (speedtest -> postgres)

[Service]
Type=oneshot
WorkingDirectory=/home/exia/net_speed
EnvironmentFile=/home/exia/net_speed/.env
ExecStart=/home/exia/net_speed/speedtest_to_pg.sh
```

`systemd/net-speed.timer`

```ini
[Unit]
Description=Run network speed measurement hourly

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
```

> `WorkingDirectory` と `EnvironmentFile` と `ExecStart` は環境に合わせて変更してください。

---

## Grafana 設定（初期設定でOK）

### Grafana起動

```bash
sudo systemctl enable --now grafana-server
```

ブラウザで以下へアクセス:

- `http://<計測端末のIP>:3000`

### PostgreSQL DataSource 追加

Grafana → **Connections / Data sources** → **PostgreSQL**

- Host: `localhost:5432`
- Database: `net_speed`
- User: `netmon`
- Password: `.env` の `DB_PASS`

### クエリ例（パネル）

ダウンロード速度（Wi-Fiだけ表示する例）:

```sql
SELECT
  measured_at AS time,
  download_mbps AS value
FROM speedtest_logs
WHERE $__timeFilter(measured_at)
  AND link_type = 'wifi'
ORDER BY 1;
```

アップロード:

```sql
SELECT
  measured_at AS time,
  upload_mbps AS value
FROM speedtest_logs
WHERE $__timeFilter(measured_at)
  AND link_type = 'wifi'
ORDER BY 1;
```

Ping:

```sql
SELECT
  measured_at AS time,
  ping_ms AS value
FROM speedtest_logs
WHERE $__timeFilter(measured_at)
  AND link_type = 'wifi'
ORDER BY 1;
```

---

## よくあるエラー

### `permission denied for sequence ...`

INSERT時にシーケンス権限がない場合があります。以下で付与します。

```bash
sudo -u postgres psql -d net_speed
```

```sql
GRANT INSERT, SELECT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO netmon;
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO netmon;
```

個別に付与する場合（例）:

```sql
GRANT USAGE, SELECT, UPDATE ON SEQUENCE speedtest_logs_id_seq TO netmon;
```

---

## バックアップ（推奨）

稼働中でも `pg_dump` で取得できます。

```bash
pg_dump -Fc -d net_speed -f net_speed_$(date +%F).dump
pg_dumpall --globals-only -f globals_$(date +%F).sql
```

復元:

```bash
psql -f globals_YYYY-MM-DD.sql
createdb -O netmon net_speed
pg_restore -d net_speed net_speed_YYYY-MM-DD.dump
```

---

## GitにREADMEを上げる

```bash
git add README.md
git commit -m "Add README"
git push origin main
```

