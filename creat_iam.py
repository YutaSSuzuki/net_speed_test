import csv
import boto3
from botocore.exceptions import ClientError

CSV_PATH = "username.csv"   # CSVファイル名
GROUP_NAME = "kensho"       # 追加するIAMグループ名
TAG_KEY = "group"
TAG_VALUE = "test"

DRY_RUN = False             # ← Trueでドライラン、Falseで本番

iam = boto3.client("iam")

def user_exists(username: str) -> bool:
    try:
        iam.get_user(UserName=username)
        return True
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchEntity":
            return False
        raise

def ensure_group(group_name: str):
    try:
        iam.get_group(GroupName=group_name)
    except ClientError as e:
        if e.response["Error"]["Code"] == "NoSuchEntity":
            if DRY_RUN:
                print(f"[DRY] would create group: {group_name}")
            else:
                iam.create_group(GroupName=group_name)
                print(f"[OK] created group: {group_name}")
        else:
            raise

def create_user(username: str):
    if DRY_RUN:
        print(f"[DRY] would create user: {username}")
        return
    iam.create_user(UserName=username)
    print(f"[OK] created user: {username}")

def add_user_to_group(username: str, group_name: str):
    if DRY_RUN:
        print(f"[DRY] would add {username} to group {group_name}")
        return
    iam.add_user_to_group(GroupName=group_name, UserName=username)
    print(f"[OK] added {username} to group {group_name}")

def tag_user(username: str, key: str, value: str):
    if DRY_RUN:
        print(f"[DRY] would tag {username}: {key}={value}")
        return
    iam.tag_user(UserName=username, Tags=[{"Key": key, "Value": value}])
    print(f"[OK] tagged {username}: {key}={value}")

def main():
    ensure_group(GROUP_NAME)

    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        if "username" not in reader.fieldnames:
            raise SystemExit("CSV must include 'username' column")

        for row in reader:
            username = (row.get("username") or "").strip()
            if not username:
                continue

            # ユーザー作成（存在してたらスキップ）
            if user_exists(username):
                print(f"[SKIP] user exists: {username}")
            else:
                create_user(username)

            # 既存ユーザーでもグループ追加＆タグ付けは実行（要件どおり）
            add_user_to_group(username, GROUP_NAME)
            tag_user(username, TAG_KEY, TAG_VALUE)

if __name__ == "__main__":
    main()
