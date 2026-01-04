# 整備中ネットワーク可視化（Speedtest + PostgreSQL + Grafana）

家庭内ネットワークの速度低下を「見える化」するための構成です。  
Speedtest（Ookla公式CLI）で定期計測し、結果を PostgreSQL に保存し、Grafana で可視化します。

- 計測: `speedtest`（Ookla公式CLI）
- 保存: PostgreSQL
- 可視化: Grafana（.deb パッケージでインストール）

> ※本構成は「インターネット回線速度（ISP速度）」の計測です。宅内LANだけを測りたい場合は iperf3 構成が適します。

---
## 後日整備する
- gitのファイル構成
- DBのスキーマのみのダンプ取得
- DBのiface、hostに挿入する内容がnullか、値を入れるかを統一していないため、統一する
- wireless、有線の計測をするための手順書になっていないため、その内容を記載する

---

## 構成

1. 計測端末（Ubuntu）で `speedtest` を実行
2. 結果(JSON)から必要項目を抽出し、PostgreSQLへINSERT
3. Grafana が PostgreSQL を参照して時系列グラフ化

---

## 前提・要件

- Ubuntu 22.04 / 24.04（他でも概ね同様）
- PostgreSQL（例: 14+）
- Grafana（.debパッケージで導入）
- Ookla Speedtest CLI（`speedtest`）
- `jq`
- `psql`（PostgreSQLクライアント）

---

## セットアップ手順（計測端末）

### 必要パッケージをインストール

```bash
sudo apt update
sudo apt install -y curl jq tar ca-certificates postgresql postgresql-client
```

---

## Speedtest（Ookla）を「バイナリ（tgz）」でインストール

APTリポジトリ方式でのインストールがうまく行かなかったため、バイナリインストールを行いました。<br>
ダウンロード方法は公式サイトを参考にダウンロードしてください

`https://www.speedtest.net/apps/cli`

### アーキテクチャ確認

```bash
uname -m
```

- `x86_64` → `linux-x86_64`
- `aarch64` → `linux-aarch64`
- `armv7l` → `linux-armhf`
- `i386` → `linux-i386`
---

## Grafana を「公式サイトの .deb パッケージ」でインストール

APTリポジトリではなく、公式サイトから `.deb` をダウンロードしてインストールします。

- ブラウザで `https://grafana.com/grafana/download` を開き、
  - OS: Debian / Ubuntu
  - Edition: OSS or Enterprise
  - Version: 任意
  を選んで **.deb のリンクをコピー**します。
- インストール方法はリンクに記載された方法に従ってください

###  grafana動作確認

```bash
sudo systemctl enable --now grafana-server
systemctl status grafana-server --no-pager
```

ブラウザでアクセス：

- `http://<計測端末のIP>:3000`

---

## PostgreSQL 初期設定（検証環境の復元）

このREADMEの目的は **「使える検証環境を作る」**ことです。  
本リポジトリ同梱の **サンプル（ロール作成SQL / ダンプ）** を使って、ロールとDBデータを復元します。

> ここではテーブルを手作業でCREATEしません（pg_dump の結果から復元します）。

### 1) 同梱ファイルの前提（例）

以下のようなファイルがリポジトリ内にある想定です（名称/場所は実態に合わせて読み替え）：

- `work/globals.sql` … ロール/権限（pg_dumpall --globals-only の結果）
- `work/net_speed.dump` … DB本体（pg_dump -Fc の結果）

### 2) ロール（ユーザー/権限）を復元

```bash
sudo -u postgres psql -f work/globals.sql
```

### 3) DB本体（データ込み）を復元

> `pg_dump -Fc` のダンプには通常 DB作成が含まれません（`-C` を付けた場合を除く）。  
> DBがまだ無い場合だけ作成してください。

```bash
# DBが存在しない場合のみ（OWNERはglobals.sqlで作られたロールに合わせる）
sudo -u postgres createdb -O netmon net_speed
```

復元：

```bash
sudo -u postgres pg_restore -d net_speed work/net_speed.dump
```

復元確認：

```bash
sudo -u postgres psql -d net_speed -c "\dt"
sudo -u postgres psql -d net_speed -c "SELECT count(*) FROM speedtest_logs;"
```

---

## .pgpass の作り方（パスワード入力を省略）

スクリプトから `psql` を叩く場合、`.pgpass` を使うとパスワード入力なしで接続できます。

### 1) 作成

個人用のため、netmonのパスワードはpasswordで設定してます<br>
`localhost:5432:net_speed:netmon:password`の部分は適宜環境に応じて変えてください。<br>
ただし、ここを変える場合はshファイルとDBのロールのパスワードも書き換えてください。

```bash
cat > ~/.pgpass <<'EOF'
localhost:5432:net_speed:netmon:password
EOF
chmod 600 ~/.pgpass
```
---

## 計測スクリプト設定

リポジトリの `speedtest_to_pg.sh` を使用します。

### 権限付与と動作確認

- 権限付与
```bash
chmod +x ./speedtest_to_pg.sh
```



- 動作確認
- 実行前にファイル内のlogfileの部分を書き換えてください

```bash
./speedtest_to_pg.sh
```

DBに入ったか確認:

```bash
psql -h localhost -U netmon -d net_speed -c "SELECT * FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
```
---

## 定期実行

CRONを設定して定期実行する。

### 設定方法

Crontabを編集。最初はどのエディタを使うか聞かれるため、好きなものを選ぶ（nanoがおすすめ）
```bash
crontab -e
```
Crontab設定内容
``` bash
PATH=/usr/local/bin:/usr/bin:/bin
## 定期実行するタイミング、1時間ごとで設定する場合の書き方
0 * * * * /home/nora/speedtest_to_pg.sh
```
### 動作確認
直近の時刻（分　時間）を設定してログ、DBを確認して挿入がされているかを確認する。
``` bash
46 22 * * * /home/nora/speedtest_to_pg.sh
```

---

## Grafana 設定（初期設定でOK）

### PostgreSQL DataSource 追加

Grafana → **Connections / Data sources** → **PostgreSQL**

- Host: `localhost:5432`（GrafanaとPostgreSQLが同一ホストの場合）
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

### `Peer authentication failed for user "netmon"`

`psql -U netmon` で失敗する場合、ローカルソケット接続が `peer` 認証になっている可能性があります。  
host を指定してTCP接続にしてください。

```bash
psql -h 127.0.0.1 -U netmon -d net_speed
```

### `Configuration - Couldn't resolve host name`（speedtest）

DNSが壊れていると speedtest が設定を取得できず失敗します。  
`ping 8.8.8.8` が通るのに `curl https://www.speedtest.net/` が失敗する場合は DNS 問題です。

---

## バックアップ（推奨）

稼働中でも `pg_dump` で取得できます。

```bash
sudo -u postgres pg_dump -Fc -d net_speed -f /var/tmp/net_speed_$(date +%F).dump
sudo -u postgres pg_dumpall --globals-only -f /var/tmp/globals_$(date +%F).sql
```

復元（例）:

```bash
sudo -u postgres psql -f /var/tmp/globals_YYYY-MM-DD.sql
sudo -u postgres createdb -O netmon net_speed
sudo -u postgres pg_restore -d net_speed /var/tmp/net_speed_YYYY-MM-DD.dump
```

---
