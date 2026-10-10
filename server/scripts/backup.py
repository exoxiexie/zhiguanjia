"""定时备份入口（由 cron 调用）

    python scripts/backup.py [label]

label 默认 auto：备份名形如 20261010-033000-auto，便于在后台区分"自动/手动"。
与后台「备份与恢复」共用 app/admin/backup_service.py，**不是第二套实现**。
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from app.admin.backup_service import create_backup  # noqa: E402

if __name__ == "__main__":
    label = sys.argv[1] if len(sys.argv) > 1 else "auto"
    rec = create_backup(label=label)
    print("备份完成：%s（%.1f KB）" % (rec["name"], rec["size"] / 1024.0))
