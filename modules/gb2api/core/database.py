"""
统计数据库操作 - 使用 storage.py 的统一数据库连接
"""
import time
from datetime import datetime
from typing import Dict, Tuple
import asyncio
from collections import defaultdict
from core.storage import _get_sqlite_conn, _sqlite_lock


class StatsDatabase:
    """统计数据库管理类 - 使用统一的 data.db"""

    async def insert_request_log(
        self, timestamp: float, model: str, ttfb_ms: int = None,
        total_ms: int = None, status: str = "success", status_code: int = None
    ):
        """插入请求记录"""
        def _insert():
            conn = _get_sqlite_conn()
            with _sqlite_lock:
                conn.execute(
                    """
                    INSERT INTO request_logs
                    (timestamp, model, ttfb_ms, total_ms, status, status_code)
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (int(timestamp), model, ttfb_ms, total_ms, status, status_code)
                )
                conn.commit()

        await asyncio.to_thread(_insert)

    async def get_stats_by_time_range(self, time_range: str = "24h") -> Dict:
        """按时间范围获取统计数据"""
        def _query():
            now = time.time()
            if time_range == "24h":
                start_time = now - 24 * 3600
                bucket_size = 3600
            elif time_range == "7d":
                start_time = now - 7 * 24 * 3600
                bucket_size = 6 * 3600
            elif time_range == "30d":
                start_time = now - 30 * 24 * 3600
                bucket_size = 24 * 3600
            else:
                start_time = now - 24 * 3600
                bucket_size = 3600

            conn = _get_sqlite_conn()
            with _sqlite_lock:
                rows = conn.execute(
                    """
                    SELECT timestamp, model, ttfb_ms, total_ms, status, status_code
                    FROM request_logs
                    WHERE timestamp >= ?
                    ORDER BY timestamp
                    """,
                    (int(start_time),)
                ).fetchall()

            # 数据分桶
            buckets = defaultdict(lambda: {
                "total": 0, "failed": 0, "rate_limited": 0,
                "models": defaultdict(int),
                "model_ttfb": defaultdict(list),
                "model_total": defaultdict(list)
            })

            for row in rows:
                ts, model, ttfb, total, status, status_code = row
                bucket_key = int((ts - start_time) // bucket_size)
                bucket = buckets[bucket_key]

                bucket["total"] += 1
                bucket["models"][model] += 1

                if status != "success":
                    bucket["failed"] += 1
                    if status_code == 429:
                        bucket["rate_limited"] += 1

                if status == "success" and ttfb is not None and total is not None:
                    bucket["model_ttfb"][model].append(ttfb)
                    bucket["model_total"][model].append(total)

            # 生成结果
            num_buckets = int((now - start_time) // bucket_size) + 1
            labels = []
            total_requests = []
            failed_requests = []
            rate_limited_requests = []

            # 先收集所有出现过的模型
            all_models = set()
            for bucket in buckets.values():
                all_models.update(bucket["models"].keys())
                all_models.update(bucket["model_ttfb"].keys())
                all_models.update(bucket["model_total"].keys())

            # 初始化每个模型的数据列表
            model_requests = {model: [] for model in all_models}
            model_ttfb_times = {model: [] for model in all_models}
            model_total_times = {model: [] for model in all_models}

            # 遍历每个时间桶
            for i in range(num_buckets):
                bucket_time = start_time + i * bucket_size
                dt = datetime.fromtimestamp(bucket_time)

                if time_range == "24h":
                    labels.append(dt.strftime("%H:00"))
                elif time_range == "7d":
                    labels.append(dt.strftime("%m-%d %H:00"))
                else:
                    labels.append(dt.strftime("%m-%d"))

                bucket = buckets[i]
                total_requests.append(bucket["total"])
                failed_requests.append(bucket["failed"])
                rate_limited_requests.append(bucket["rate_limited"])

                # 为每个模型添加数据（存在则添加实际值，不存在则添加0）
                for model in all_models:
                    # 请求数
                    model_requests[model].append(bucket["models"].get(model, 0))

                    # TTFB平均时间
                    if model in bucket["model_ttfb"] and bucket["model_ttfb"][model]:
                        avg_ttfb = sum(bucket["model_ttfb"][model]) / len(bucket["model_ttfb"][model])
                        model_ttfb_times[model].append(avg_ttfb)
                    else:
                        model_ttfb_times[model].append(0)

                    # 总响应平均时间
                    if model in bucket["model_total"] and bucket["model_total"][model]:
                        avg_total = sum(bucket["model_total"][model]) / len(bucket["model_total"][model])
                        model_total_times[model].append(avg_total)
                    else:
                        model_total_times[model].append(0)

            # 数据已经是按时间顺序（旧→新），不需要反转
            # ECharts 从左到右渲染，所以最旧的在左边，最新的在右边

            return {
                "labels": labels,
                "total_requests": total_requests,
                "failed_requests": failed_requests,
                "rate_limited_requests": rate_limited_requests,
                "model_requests": dict(model_requests),
                "model_ttfb_times": dict(model_ttfb_times),
                "model_total_times": dict(model_total_times)
            }

        return await asyncio.to_thread(_query)

    async def get_total_counts(self) -> Tuple[int, int]:
        """获取总成功和失败次数"""
        def _query():
            conn = _get_sqlite_conn()
            with _sqlite_lock:
                success = conn.execute(
                    "SELECT COUNT(*) FROM request_logs WHERE status = 'success'"
                ).fetchone()[0]
                failed = conn.execute(
                    "SELECT COUNT(*) FROM request_logs WHERE status != 'success'"
                ).fetchone()[0]
            return success, failed

        return await asyncio.to_thread(_query)

    async def cleanup_old_data(self, days: int = 30):
        """清理过期数据 - 默认保留30天"""
        def _cleanup():
            cutoff_time = int(time.time() - days * 24 * 3600)
            conn = _get_sqlite_conn()
            with _sqlite_lock:
                cursor = conn.execute(
                    "DELETE FROM request_logs WHERE timestamp < ?",
                    (cutoff_time,)
                )
                conn.commit()
                return cursor.rowcount

        return await asyncio.to_thread(_cleanup)


# 全局实例
stats_db = StatsDatabase()
