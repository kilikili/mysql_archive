#!/bin/bash
# expd.sh - 使用 pt-archiver 刪除資料
# 支援命令列參數或設定檔兩種執行方式

# 顯示使用說明
show_usage() {
  echo "用法："
  echo "  方式1 (命令列): $0 <table_name> <due_date> <batch_limit> <idx> <date_field>"
  echo "  方式2 (設定檔): $0 -c <config_file>"
  echo ""
  echo "範例："
  echo "  $0 mp_icp_order 2015-07-08 1000 IDX_2_MP_ICP_ORDER FLD_ORDER_DATE_TIME"
  echo "  $0 -c /etc/pt-archiver/mp_icp_order.conf"
  echo "  $0 --config ./configs/cleanup.conf"
  exit 1
}

# 解析參數
if [ "$1" = "-c" ] || [ "$1" = "--config" ]; then
  # 使用設定檔模式
  CONFIG_FILE="$2"
  
  if [ -z "$CONFIG_FILE" ] || [ ! -f "$CONFIG_FILE" ]; then
    echo "錯誤：設定檔不存在 - $CONFIG_FILE"
    show_usage
  fi
  
  echo "讀取設定檔：$CONFIG_FILE"
  source "$CONFIG_FILE"
  
else
  # 使用命令列參數模式
  TABLE_NAME="$1"
  DUE_DATE="$2"
  BATCH_LIMIT=$3
  IDX="$4"
  DATE_FIELD="$5"
  
  # 驗證參數
  if [ -z "$TABLE_NAME" ] || [ -z "$DUE_DATE" ] || [ -z "$BATCH_LIMIT" ] || [ -z "$IDX" ] || [ -z "$DATE_FIELD" ]; then
    echo "錯誤：缺少必要參數"
    show_usage
  fi
fi

# 設定預設值（如果設定檔沒有提供）
DB_HOST=${DB_HOST:-127.0.0.1}
DB_USER=${DB_USER:-pt_archiver}
DB_PASSWORD=${DB_PASSWORD:-}
DB_NAME=${DB_NAME:-micropay}
ARCHIVE_DB=${ARCHIVE_DB:-micropay_archive}
MODE=${MODE:-purge}
CHARSET=${CHARSET:-utf8}
RUN_TIME=${RUN_TIME:-}
SLEEP=${SLEEP:-0}
DRY_RUN=${DRY_RUN:-yes}

# 驗證必要參數
if [ -z "$TABLE_NAME" ] || [ -z "$DUE_DATE" ] || [ -z "$BATCH_LIMIT" ] || [ -z "$IDX" ] || [ -z "$DATE_FIELD" ]; then
  echo "錯誤：設定檔缺少必要參數"
  echo "必要參數：TABLE_NAME, DUE_DATE, BATCH_LIMIT, IDX, DATE_FIELD"
  exit 1
fi

# 顯示執行資訊
echo "========================================="
echo "執行資訊："
echo "  資料表：$TABLE_NAME"
echo "  條件：$DATE_FIELD < $DUE_DATE"
echo "  批次大小：$BATCH_LIMIT"
echo "  索引：$IDX"
echo "  模式：$MODE"
echo "========================================="

# 設定密碼環境變數
if [ -n "$DB_PASSWORD" ]; then
  export MYSQL_PWD="$DB_PASSWORD"
fi

# 建立 pt-archiver 基本參數
PT_ARCHIVER_OPTS=(
  --source "h=$DB_HOST,D=$DB_NAME,t=$TABLE_NAME,i=$IDX,u=$DB_USER"
  --where "$DATE_FIELD < '$DUE_DATE'"
  --limit="$BATCH_LIMIT"
  --commit-each
  --progress="$BATCH_LIMIT"
  --statistics
)

# 根據模式添加參數
case "$MODE" in
  purge)
    # 純刪除模式
    PT_ARCHIVER_OPTS+=(--purge)
    ;;
  archive)
    # 歸檔模式
    PT_ARCHIVER_OPTS+=(--dest "h=$DB_HOST,D=$ARCHIVE_DB,t=$TABLE_NAME,u=$DB_USER")
    ;;
  archive-only)
    # 只歸檔不刪除
    PT_ARCHIVER_OPTS+=(--dest "h=$DB_HOST,D=$ARCHIVE_DB,t=$TABLE_NAME,u=$DB_USER")
    PT_ARCHIVER_OPTS+=(--no-delete)
    ;;
  *)
    echo "錯誤：不支援的模式 - $MODE"
    echo "支援的模式：purge, archive, archive-only"
    exit 1
    ;;
esac

# 添加字元集
if [ -n "$CHARSET" ]; then
  PT_ARCHIVER_OPTS+=(--charset="$CHARSET")
fi

# 添加執行時間限制
if [ -n "$RUN_TIME" ] && [ "$RUN_TIME" -gt 0 ]; then
  PT_ARCHIVER_OPTS+=(--run-time="$RUN_TIME")
fi

# 添加延遲
if [ -n "$SLEEP" ] && [ "$SLEEP" != "0" ]; then
  PT_ARCHIVER_OPTS+=(--sleep="$SLEEP")
fi

# Dry run 模式
if [ "$DRY_RUN" = "yes" ] || [ "$DRY_RUN" = "true" ] || [ "$DRY_RUN" = "1" ]; then
  PT_ARCHIVER_OPTS+=(--dry-run)
  echo "*** DRY RUN 模式 - 不會實際刪除資料 ***"
fi

# 執行 pt-archiver
echo ""
echo "開始執行 pt-archiver..."
echo "命令：pt-archiver ${PT_ARCHIVER_OPTS[@]}"
echo ""

pt-archiver "${PT_ARCHIVER_OPTS[@]}"
EXIT_CODE=$?

# 清除密碼環境變數
unset MYSQL_PWD

# 顯示結果
echo ""
echo "========================================="
if [ $EXIT_CODE -eq 0 ]; then
  echo "執行完成！"
  echo "完成時間：$(date '+%Y-%m-%d %H:%M:%S')"
else
  echo "執行失敗！錯誤代碼：$EXIT_CODE"
fi
echo "========================================="

exit $EXIT_CODE
