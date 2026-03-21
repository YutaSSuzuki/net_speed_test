# ネットワーク可視化（Speedtest + PostgreSQL + Grafana）

## 0. 目次

- [1. 概要](#1-概要)
- [2. 全体構成](#2-全体構成)
- [3. 前提・要件](#3-前提要件)
- [4. ソフトウェアのインストール](#4-ソフトウェアのインストール)
- [5. PostgresDBの構築](#5-postgresdbの構築)
- [6. scriptディレクトリのスクリプト設定](#6-scriptディレクトリのスクリプト設定)
- [7. Grafana 設定](#7-grafana-設定)
- [8. DBバックアップ、復元の方法](#8-dbバックアップ復元の方法)
- [9. よくあるエラー](#9-よくあるエラー)
- [10. 注意事項](#10-注意事項)

## 1. 概要

### 注意

本READMEは ChatGPT と Codex を活用して作成しています。  
このREADMEの手順を通しで動作確認できているわけではないため、環境差分や制作者特有の設定によってエラーが出る場合があります。  
エラーや不足があれば、Issue や Pull Request で共有してください。


### このリポジトリの概要
家のネット速度が遅いことがあり、原因調査のため外部インターネット回線の速度を見える化するためのアプリを作りました。  
`speedtest` で定期計測し、結果を PostgreSQL に保存し、Grafana で時系列表示します。<br>
7.grafanaの設定まで行えば自動計測と可視化が可能です。

- 計測: Ookla Speedtest CLI
- 保存: PostgreSQL
- 可視化: Grafana


### この構成でできること

- 回線速度の定点観測
- ダウンロード速度、アップロード速度、Ping の蓄積
- Grafana での時系列グラフ表示
- cron による定期実行
- 無線 / 有線を分けた計測スクリプトへの拡張

## 2. 全体構成

1. Ubuntu 端末で `speedtest` を実行する
2. 実行結果の JSON から必要項目を抽出する
3. PostgreSQL の `speedtest_logs` テーブルへ INSERT する
4. Grafana から PostgreSQL を参照して可視化する

### ディレクトリ構成

```text
net_speed_test/
├── README.md
├── creat_iam.py
├── db/
│   ├── globals.sql
│   ├── net_speed_data.dump
│   └── net_speed_schema.sql
├── script/
│   ├── check_iface.sh
│   └── speedtest_wireless_wired.sh
└── speed_log/
    └── speedtest_agent.log
```

各ディレクトリの役割:

- `db/`: PostgreSQL 復元用ファイル
- `script/`: 計測スクリプト
- `speed_log/`: 実行ログ保存先

## 3. 前提・要件

- Ubuntu 22.04 / 24.04
- PostgreSQL
- Grafana
- Ookla Speedtest CLI
- `jq`
- `psql` コマンド

## 4. ソフトウェアのインストール

この章では以下を導入します。

- PostgreSQL
- Grafana
- Ookla Speedtest CLI
- `jq`
- `psql` コマンド

### 4.1 PostgreSQL

インストール:

```bash
sudo apt update
sudo apt install -y postgresql postgresql-client
```

動作確認:

```bash
# psql コマンドが使えるか確認
psql --version

# PostgreSQL サービスが起動しているか確認
sudo systemctl status postgresql --no-pager

# PostgreSQL に接続できるか確認
sudo -u postgres psql -c "\l"
```

成功例:

```text
# psql --version
psql (PostgreSQL) 16.x

# sudo systemctl status postgresql --no-pager
Active: active (running)

# sudo -u postgres psql -c "\l"
List of databases
   Name    |  Owner   | Encoding
-----------+----------+----------
 postgres  | postgres | UTF8
 template0 | postgres | UTF8
 template1 | postgres | UTF8
```

### 4.2 Grafana

Grafana は公式サイトの `.deb` パッケージから導入します。

1. `https://grafana.com/grafana/download` を開く
2. OS に Debian / Ubuntu を選ぶ
3. 必要な Edition と Version を選ぶ
4. 表示された `.deb` のリンクを使ってインストールする

導入後の起動:

```bash
sudo systemctl enable --now grafana-server
```

動作確認:

```bash
# Grafana のバージョン確認
grafana-server -v

# Grafana サービスが起動しているか確認
sudo systemctl status grafana-server --no-pager

# Grafana の Web UI に応答があるか確認
curl -I http://127.0.0.1:3000
```

成功例:

```text
# grafana-server -v
Version 11.x.x (commit: xxxxxxx, branch: HEAD)

# sudo systemctl status grafana-server --no-pager
Active: active (running)

# curl -I http://127.0.0.1:3000
HTTP/1.1 302 Found
Location: /login
```

ブラウザアクセス:

- `http://<計測端末のIP>:3000`

### 4.3 Ookla Speedtest CLI

APT リポジトリ方式での導入が安定しなかったため、バイナリ配布版を前提にしています。  
公式サイトから環境に合うパッケージを取得してください。

`https://www.speedtest.net/apps/cli`

アーキテクチャ確認:

```bash
uname -m
```

- `x86_64` → `linux-x86_64`
- `aarch64` → `linux-aarch64`
- `armv7l` → `linux-armhf`
- `i386` → `linux-i386`

展開後に `speedtest` コマンドが通る場所へ配置します。

動作確認:

```bash
# Speedtest CLI のバージョン確認
speedtest --version

# 実際に速度計測ができるか確認
speedtest --accept-license --accept-gdpr
```

成功例:

```text
# speedtest --version
Speedtest by Ookla x.x.x

# speedtest --accept-license --accept-gdpr
Server: xxxxx
ISP: xxxxx
Download: 123.45 Mbps
Upload: 67.89 Mbps
Ping: 12.34 ms
```

### 4.4 jq

インストール:

```bash
sudo apt update
sudo apt install -y jq
```

動作確認:

```bash
# jq のバージョン確認
jq --version

# jq で JSON を整形できるか確認
echo '{"ok": true}' | jq .
```

成功例:

```text
# jq --version
jq-1.6

# echo '{"ok": true}' | jq .
{
  "ok": true
}
```

### 4.5 psql コマンド

`psql` は PostgreSQL クライアントに含まれます。未導入の場合は以下を実行します。

インストール:

```bash
sudo apt update
sudo apt install -y postgresql-client
```

動作確認:

```bash
# psql コマンドのバージョン確認
psql --version

# psql コマンドの配置場所を確認
which psql
```

成功例:

```text
# psql --version
psql (PostgreSQL) 16.x

# which psql
/usr/bin/psql
```

## 5. PostgresDBの構築

この章では、`db/globals.sql` と `db/net_speed_schema.sql` を使って、計測スクリプトがそのまま動く空の `net_speed` DB を作成します。  
ここで作るのは「データなし・スキーマあり」の初期状態です。<br>
`db/net_speed_data.dump`はサンプル用のデータのためここでは使いません。

使用するファイル:

- `db/globals.sql`: 計測用ロール `netmon` の作成
- `db/net_speed_schema.sql`: `speedtest_logs` テーブル、シーケンス、権限

### 5.1 DBの構築手順

```bash
# PostgreSQL の管理ユーザーで netmon ロールを作成
sudo -u postgres psql -f db/globals.sql

# net_speed データベースを作成
sudo -u postgres createdb net_speed

# 実運用に合わせたスキーマを作成
sudo -u postgres psql -d net_speed -f db/net_speed_schema.sql
```

動作確認:

```bash
# speedtest_logs テーブル定義を確認
sudo -u postgres psql -d net_speed -c "\d+ speedtest_logs"

# netmon に必要な権限が入っているか確認
sudo -u postgres psql -d net_speed -c "\dp public.speedtest_logs"

# netmon で接続できるか確認
psql -h localhost -U netmon -d net_speed -c "SELECT count(*) FROM speedtest_logs;"
```

成功例:

```text
# sudo -u postgres psql -d net_speed -c "\d+ speedtest_logs"
Table "public.speedtest_logs"
    Column     | Type | Nullable | Default
---------------+------+----------+--------------------------------------------
 id            | integer | not null | nextval('speedtest_logs_id_seq'::regclass)
 measured_at   | timestamp without time zone | not null |
 download_mbps | numeric | |
 upload_mbps   | numeric | |
 ping_ms       | numeric | |
 link_type     | text | not null | 'wired'::text
 iface         | text | |
 host          | text | |

# sudo -u postgres psql -d net_speed -c "\dp public.speedtest_logs"
postgres=arwdDxt/postgres
netmon=ar/postgres

# psql -h localhost -U netmon -d net_speed -c "SELECT count(*) FROM speedtest_logs;"
 count
-------
     0
```

補足:

- `sudo -u postgres psql -f db/globals.sql` は OS の `postgres` ユーザーとしてローカル接続するため、通常は PostgreSQL の初期パスワードは不要です
- `globals.sql` で作成される `netmon` のパスワードは、`.pgpass` の設定値と合わせて使います
- `net_speed_schema.sql` は `public` スキーマに `speedtest_logs` を作成します

### 5.2 DBの使用説明

この構成で主に使うテーブルは `public.speedtest_logs` です。  
計測スクリプトはこのテーブルに対して INSERT を行い、Grafana はこのテーブルを参照して可視化します。

使用テーブル:

- `speedtest_logs`

カラム説明:

| カラム名 | 内容 |
| --- | --- |
| `id` | 主キー |
| `measured_at` | 計測時刻 |
| `download_mbps` | ダウンロード速度 |
| `upload_mbps` | アップロード速度 |
| `ping_ms` | Ping |
| `link_type` | 接続種別。`wireless` または `wired` |
| `iface` | 計測に使ったインターフェース名。例: `wlp2s0`, `enp0s31f6` |
| `host` | 計測端末名。現状のスクリプトでは `NULL` を入れる |

運用ルール:

- `link_type` は `wireless` / `wired` の値で保存します
- `iface` は空欄にせず、利用した NIC 名を保存します
- `host` は将来拡張用の列です。現状使用しておらず `NULL` で問題ありません
- テーブルは `public` スキーマに作成されます

## 6. scriptディレクトリのスクリプト設定

この章では、`script/speedtest_wireless_wired.sh` を実行して `speedtest_logs` にデータを INSERT できる状態まで設定します。  
実運用ではこのスクリプトを cron から定期実行しています。

### 6.1 `.pgpass` を設定する

スクリプトは `psql` をパスワード入力なしで実行するため、ホームディレクトリに `.pgpass` が必要です。  
今回はサンプルのためパスワードをpasswordで設定しています。

```bash
cat > ~/.pgpass <<'EOF'
localhost:5432:net_speed:netmon:password
EOF
chmod 600 ~/.pgpass
```

動作確認:

```bash
# netmon で DB に接続できるか確認
psql -h localhost -U netmon -d net_speed -c "SELECT current_user, current_database();"
```

成功例:

```text
# psql -h localhost -U netmon -d net_speed -c "SELECT current_user, current_database();"
 current_user | current_database
--------------+------------------
 netmon       | net_speed
```

### 6.2 スクリプトの実行前設定

実行権限を付けます。

```bash
chmod +x script/check_iface.sh
chmod +x script/speedtest_wireless_wired.sh
```

次に、利用するインターフェース名を確認します。

```bash
./script/check_iface.sh
```

成功例:

```text
lo : wired
enp0s31f6 : wired
wlp2s0 : wireless
```

確認した値を `script/speedtest_wireless_wired.sh` の `WIFI_IF` と `WIRED_IF` に反映してください。

### 6.3 手動実行して INSERT できることを確認する

スクリプトを手動で 1 回実行します。

```bash
./script/speedtest_wireless_wired.sh
```

ログ確認:

```bash
tail -n 30 speed_log/speedtest_agent.log
```

DB 確認:

```bash
psql -h localhost -U netmon -d net_speed -c "SELECT measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
```

成功例:

```text
# tail -n 30 speed_log/speedtest_agent.log
[Thu Mar 20 21:00:01 JST 2026] ===== start dual speedtest =====
[Thu Mar 20 21:00:01 JST 2026] --- wireless test start (iface=wlp2s0) ---
Download: 516.69 Mbps, Upload: 32.08 Mbps, Ping: 17.027 ms
[Thu Mar 20 21:00:30 JST 2026] --- wireless test end ---
[Thu Mar 20 21:00:30 JST 2026] --- wired test start (iface=enp0s31f6) ---
Download: 886.02 Mbps, Upload: 948.88 Mbps, Ping: 8.512 ms
[Thu Mar 20 21:00:44 JST 2026] --- wired test end ---
[Thu Mar 20 21:00:44 JST 2026] ===== end dual speedtest =====

# psql -h localhost -U netmon -d net_speed -c "SELECT measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
        measured_at         | download_mbps | upload_mbps | ping_ms | link_type |   iface   | host
----------------------------+---------------+-------------+---------+-----------+-----------+------
 2026-03-20 20:00:44.20815  |        886.02 |      948.88 |   8.512 | wired     | enp0s31f6 |
 2026-03-20 20:00:30.394369 |         40.69 |       32.08 |  17.027 | wireless  | wlp2s0    |
```

### 6.4 cron に登録する

定期実行する場合は `crontab` に登録します。

```bash
crontab -e
```

1 時間ごとに実行する例:

```cron
PATH=/usr/local/bin:/usr/bin:/bin
0 * * * * /home/<user>/net_speed_test/script/speedtest_wireless_wired.sh
```

cron 設定確認:

```bash
crontab -l
```

成功例:

```text
# crontab -l
PATH=/usr/local/bin:/usr/bin:/bin
0 * * * * /home/<user>/net_speed_test/script/speedtest_wireless_wired.sh
```

cronの動作確認:
直近の時刻（分　時間）を設定してログ、DBを確認して挿入がされているかを確認する。<br>
以下は22:46に実行するときの例
```bash
46 22 * * * /home/<user>/net_speed_test/script/speedtest_wireless_wired.sh
```

成功例:<br>
直近の測定結果が挿入されている

```text
# psql -h localhost -U netmon -d net_speed -c "SELECT measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
        measured_at         | download_mbps | upload_mbps | ping_ms | link_type |   iface   | host
----------------------------+---------------+-------------+---------+-----------+-----------+------
 2026-03-20 22:46:44.20815  |        900.02 |      948.88 |   8.512 | wired     | enp0s31f6 |
 2026-03-20 20:46:30.394369 |         50.69 |       32.08 |  17.027 | wireless  | wlp2s0    |
 2026-03-20 20:00:44.20815  |        886.02 |      948.88 |   8.512 | wired     | enp0s31f6 |
 2026-03-20 20:00:30.394369 |         40.69 |       32.08 |  17.027 | wireless  | wlp2s0    |
```

## 7. Grafana 設定

Grafanaの設定が完了すれば１時間に１回自動でネット速度を計測し、可視化することができます。<br>
ここまでできればセットアップは完了です。

### 7.1 DataSource 設定

Grafana で PostgreSQL DataSource を追加します。  
実運用では PostgreSQL を参照する DataSource を 1 つ作成し、`net speed` ダッシュボードから利用しています。

- Host: `localhost:5432`
- Database: `net_speed`
- User: `netmon`
- Password: PostgreSQL に設定したパスワード
- SSL Mode: 環境に応じて設定。ローカル接続のみなら `disable` で可

Grafana 側の確認ポイント:

- Data source type: `PostgreSQL`
- Save & test が成功すること
- ダッシュボードでクエリ結果が取得できること

### 7.2 クエリ例

実運用では `Download`、`Upload`、`Ping` の各パネルで、`wireless` と `wired` を別 series として表示しています。
有線と無線の片方でしか計測しない場合は以下のどちらか一方だけで問題ないです。  

Download パネル:

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  download_mbps AS "wireless"
FROM speedtest_logs
WHERE link_type = 'wireless'
ORDER BY measured_at;
```

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  download_mbps AS "wired"
FROM speedtest_logs
WHERE link_type = 'wired'
ORDER BY measured_at;
```

Upload パネル:

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  upload_mbps AS "wireless"
FROM speedtest_logs
WHERE $__timeFilter(measured_at)
  AND link_type = 'wireless'
ORDER BY measured_at;
```

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  upload_mbps AS "wired"
FROM speedtest_logs
WHERE link_type = 'wired'
ORDER BY measured_at;
```

Ping パネル:

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  ping_ms AS "wireless"
FROM speedtest_logs
WHERE link_type = 'wireless'
ORDER BY measured_at;
```

```sql
SELECT
  measured_at AT TIME ZONE 'Asia/Tokyo' AS "time",
  ping_ms AS "wired"
FROM speedtest_logs
WHERE link_type = 'wired'
ORDER BY measured_at;
```

## 8. DBバックアップ、復元の方法

この章では、現在運用している端末から `net_speed` のデータを抜き出し、別端末で復元する方法を書きます。  

### 8.1 運用端末からデータをバックアップする

運用端末では、データ本体を `pg_dump --data-only -Fc` で取得します。  
ロールとスキーマはこのリポジトリの `db/globals.sql` と `db/net_speed_schema.sql` を使う前提なので、ここではデータ本体だけを抜き出します。

`exia` 端末で取得する例:

```bash
sudo -u postgres pg_dump --data-only -Fc -d net_speed -f /var/tmp/net_speed_data.dump
```

動作確認:

```bash
ls -lh /var/tmp/net_speed_data.dump
```

成功例:

```text
-rw-r--r-- 1 postgres postgres 120K Mar 21 10:00 /var/tmp/net_speed_data.dump
```

### 8.2 バックアップファイルを `db/` ディレクトリに配置する

取得したダンプファイルを、このリポジトリの `db/` 配下へコピーします。  
ファイル名は分かりやすくしておくと管理しやすいです。

例:

```bash
scp exia:/var/tmp/net_speed_data.dump ./db/net_speed_data.dump
```

動作確認:

```bash
ls -lh db/net_speed_data.dump
```

成功例:

```text
-rw-r--r-- 1 <user> <user> 120K Mar 21 10:05 db/net_speed_data.dump
```

### 8.3 `db/` 配下のデータを使って復元する

先に `5. PostgresDBの構築` の手順で、`globals.sql` と `net_speed_schema.sql` を使った空の `net_speed` DB を作成しておきます。  
その上で、`db/` に置いたダンプを `pg_restore` で流し込みます。

復元手順:

```bash
# まだ空DBを作っていない場合は先に実施
sudo -u postgres psql -f db/globals.sql
sudo -u postgres createdb net_speed
sudo -u postgres psql -d net_speed -f db/net_speed_schema.sql

# 別端末から持ってきたデータを復元
sudo -u postgres pg_restore -d net_speed db/net_speed_data.dump
```

動作確認:

```bash
# 件数確認
sudo -u postgres psql -d net_speed -c "SELECT count(*) FROM speedtest_logs;"

# 直近データ確認
sudo -u postgres psql -d net_speed -c "SELECT measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
```

成功例:

```text
# sudo -u postgres psql -d net_speed -c "SELECT count(*) FROM speedtest_logs;"
 count
-------
  3975

# sudo -u postgres psql -d net_speed -c "SELECT measured_at, download_mbps, upload_mbps, ping_ms, link_type, iface, host FROM speedtest_logs ORDER BY measured_at DESC LIMIT 5;"
        measured_at         | download_mbps | upload_mbps | ping_ms | link_type |   iface   | host
----------------------------+---------------+-------------+---------+-----------+-----------+------
 2026-03-20 20:00:44.20815  |        886.02 |      948.88 |   8.512 | wired     | enp0s31f6 |
 2026-03-20 20:00:30.394369 |        516.69 |       32.08 |  17.027 | wireless  | wlp2s0    |
```

補足:

- 既存の `net_speed` に上書きしたくない場合は、別名の DB を作ってそこへ `pg_restore` してください
- `pg_restore` 先のスキーマは、ダンプ取得元と同じ列構成である必要があります
- このリポジトリでは、実運用に合わせた空スキーマを `db/net_speed_schema.sql` で用意しています

## 9. よくあるエラー

### `Peer authentication failed for user "netmon"`

`psql -U netmon` で失敗する場合、Unix ソケット接続で `peer` 認証になっている可能性があります。  
`-h 127.0.0.1` または `-h localhost` を付けて TCP 接続してください。

```bash
psql -h 127.0.0.1 -U netmon -d net_speed
```

### `Configuration - Couldn't resolve host name`

`speedtest` 実行時に DNS 解決に失敗している状態です。  
`ping 8.8.8.8` は通るのに `curl https://www.speedtest.net/` が失敗する場合は DNS 設定を確認してください。

### `column "link_type" does not exist`

`speedtest_wireless_wired.sh` は `link_type`, `iface`, `host` を INSERT します。  
復元した DB が旧スキーマのままだとこのエラーになります。スクリプトか DB スキーマのどちらかを統一してください。

## 10. 注意事項

- `speed_log/speedtest_agent.log` はログが蓄積するため、必要に応じてローテーションを検討してください
- `.pgpass` には認証情報を保存するため、権限は必ず `600` にしてください
- `speedtest` の実行結果は回線状況や計測先サーバの影響を受けます
  - 高頻度で`speedtest`を行うと計測先のサーバーからブロックされる可能性があります。頻度を上げるときは注意してください
